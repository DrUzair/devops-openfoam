#!/bin/bash

# OpenFOAM Parametric Study - Container Environment
#set -e  # Exit if any command fails
echo "DEBUG: Script started"
set -x
# ✅ Force workspace to /opt/simulation
WORKSPACE="/opt/simulation"
RESULTS_DIR="${WORKSPACE}/runs"
LOG_FILE="${RESULTS_DIR}/parametric-study.log"

# ✅ Always create results directory
mkdir -p "${RESULTS_DIR}"
echo "✓ Created results directory: ${RESULTS_DIR}"

# ✅ Optional: Log the start time
echo "Parametric study started at $(date)" > "${LOG_FILE}"
echo "=== STARTING PARAMETRIC STUDY ==="
echo "Timestamp: $(date)"
echo "Container: $(hostname)"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"

# Source OpenFOAM environment (less strict)
echo "Loading OpenFOAM environment..."
set +u  # Allow unbound variables for OpenFOAM sourcing
#source /opt/openfoam9/etc/bashrc
echo "Sourcing OpenFOAM..."
ls -l /opt/openfoam9/etc/bashrc || echo "bashrc not found"
source /opt/openfoam9/etc/bashrc || echo "Source command failed"

echo "✓ OpenFOAM sourced"
which icoFoam
echo "WM_PROJECT_VERSION=$WM_PROJECT_VERSION"
set -u  # Re-enable after sourcing
echo "✓ OpenFOAM $WM_PROJECT_VERSION loaded"


# Install bc calculator if not available
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apt-get update -qq && apt-get install -y bc
    echo "✓ bc calculator installed"
fi

# Configuration - Auto-detect environment
if [ -d "/workspace" ]; then
    WORKSPACE="/workspace"
    BASE_CASE="${WORKSPACE}/cavity-flow-case"
elif [ -d "/opt/simulation" ]; then
    WORKSPACE="/opt/simulation"
    BASE_CASE="${WORKSPACE}/cases/cavity-flow"
else
    echo "ERROR: Cannot find workspace directory"
    echo "Available directories:"
    ls -la /
    exit 1
fi

RESULTS_DIR="${WORKSPACE}/runs"
LOG_FILE="${RESULTS_DIR}/parametric-study.log"

echo "Detected workspace: ${WORKSPACE}"
echo "Base case location: ${BASE_CASE}"
echo "Results directory: ${RESULTS_DIR}"

# Create results directory
mkdir -p "${RESULTS_DIR}"
echo "✓ Created results directory: ${RESULTS_DIR}"

# Logging function
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$msg"
    echo "$msg" >> "${LOG_FILE}" 2>/dev/null || true
}

log "Starting OpenFOAM parametric study"
log "Workspace: ${WORKSPACE}"
log "Base case: ${BASE_CASE}"

# Check workspace contents
echo "Workspace contents:"
ls -la "${WORKSPACE}/" || echo "Cannot list workspace"

# Check if base case exists or create from tutorial
if [ ! -d "${BASE_CASE}" ]; then
    log "Base case not found at ${BASE_CASE}"
    log "Available OpenFOAM tutorials location: ${FOAM_TUTORIALS}"
    
    # Try to find and copy cavity tutorial
    TUTORIAL_CASE="${FOAM_TUTORIALS}/incompressible/icoFoam/cavity/cavity"
    if [ -d "${TUTORIAL_CASE}" ]; then
        log "Copying tutorial case from ${TUTORIAL_CASE}"
        mkdir -p "$(dirname "${BASE_CASE}")"
        cp -r "${TUTORIAL_CASE}" "${BASE_CASE}"
        log "✓ Tutorial case copied successfully"
    else
        log "ERROR: Cannot find cavity tutorial at ${TUTORIAL_CASE}"
        log "Available tutorials:"
        find "${FOAM_TUTORIALS}" -name "*cavity*" -type d | head -5 || echo "No cavity tutorials found"
        exit 1
    fi
fi

log "✓ Base case verified: ${BASE_CASE}"

# Validation function
validate_results() {
    local case_dir=$1
    local reynolds=$2
    
    # Check if simulation completed (look for time directories)
    local time_dirs=($(ls -1 "${case_dir}" 2>/dev/null | grep -E '^[0-9]+\.?[0-9]*$' | sort -n))
    
    if [ ${#time_dirs[@]} -eq 0 ]; then
        log "ERROR: No time directories found for Re=${reynolds}"
        return 1
    fi
    
    local final_time="${time_dirs[-1]}"
    
    # Check if velocity field exists in final time
    if [ ! -f "${case_dir}/${final_time}/U" ]; then
        log "ERROR: Velocity field not found for Re=${reynolds} at time ${final_time}"
        return 1
    fi
    
    log "SUCCESS: Valid results for Re=${reynolds}, final time=${final_time}"
    return 0
}

# Main parametric study function
main() {
    log "Starting parametric study execution"
    
    # Reynolds numbers to test
    local reynolds_numbers=(100 200 500 1000)
    log "Testing Reynolds numbers: ${reynolds_numbers[*]}"
    
    # Initialize summary CSV
    local summary_file="${RESULTS_DIR}/summary.csv"
    echo "Reynolds,Status,Runtime,FinalTime,CaseDir" > "${summary_file}"
    
    local success_count=0
    local total_count=${#reynolds_numbers[@]}
    
    for re in "${reynolds_numbers[@]}"; do
        echo ""
        log "=== Processing Reynolds number: ${re} ==="
        
        # Create case directory
        local case_name="cavity_Re_${re}"
        local case_dir="${RESULTS_DIR}/${case_name}"
        
        # Remove existing case
        if [ -d "${case_dir}" ]; then
            log "Removing existing case: ${case_dir}"
            rm -rf "${case_dir}"
        fi
        
        # Copy base case
        log "Copying base case to ${case_dir}"
        cp -r "${BASE_CASE}" "${case_dir}"
        
        # Navigate to case directory
        cd "${case_dir}"
        log "Working in: $(pwd)"
        
        # Show case structure
        log "Case contents:"
        ls -la . || echo "Cannot list case contents"
        
        # Update Reynolds number in transportProperties
        log "Setting Reynolds number to ${re}"
        #local nu_value=$(echo "scale=8; 1.0/${re}" | bc -l)
        local nu_value=$(echo "scale=10; 0.001/${re}" | bc -l)
        echo "Calculated kinematic viscosity: ${nu_value}"
        transport_file="constant/transportProperties"
        log "DEBUG: transportProperties nu content:"
        head -10 constant/transportProperties
# Update Reynolds number in transportProperties
log "Setting Reynolds number to ${re}"
nu_value=$(echo "scale=8; 1.0/${re}" | bc -l)
log "Calculated kinematic viscosity: ${nu_value}"

# Update Reynolds number in transportProperties
log "Setting Reynolds number to ${re}"
nu_value=$(echo "scale=10; 1.0/${re}" | bc -l)
log "Calculated kinematic viscosity: ${nu_value}"

transport_file="constant/transportProperties"

# Create new transportProperties with proper OpenFOAM formatting
cat > "$transport_file" <<EOF
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "constant";
    object      transportProperties;
}

transportModel  Newtonian;

nu              nu [0 2 -1 0 0 0 0] ${nu_value};
EOF

# Verify the file was written correctly
log "Transport properties file content:"
cat "$transport_file"

# Additional verification step
if ! grep -q "nu.*${nu_value}" "$transport_file"; then
    log "ERROR: Failed to correctly set viscosity in transportProperties"
    exit 1
fi

# Ensure proper line endings (convert DOS to UNIX if needed)
sed -i 's/\r$//' "$transport_file"        # Run simulation with timing
        log "Starting blockMesh for Re=${re}"
        local start_time=$(date +%s)
        
        # Run blockMesh
        if blockMesh > log.blockMesh 2>&1; then
            log "✓ blockMesh completed successfully"
        else
            log "ERROR: blockMesh failed for Re=${re}"
            echo "blockMesh log (last 10 lines):"
            tail -10 log.blockMesh
            echo "${re},FAILED,N/A,N/A,${case_dir}" >> "${summary_file}"
            continue
        fi
        
        # Debug: show current directory and contents
        echo "PWD before running icoFoam: $(pwd)"
        echo "Contents:"
        ls -la
        echo "System directory:"
        ls -la system
        echo "Constant directory:"
        ls -la constant

        # Run icoFoam with timeout and capture exit code
        timeout 300 icoFoam > log.icoFoam 2>&1
        exit_code=$?
        echo "icoFoam exit code: $exit_code"
        tail -20 log.icoFoam

        # Run icoFoam solver
        log "Running icoFoam solver for Re=${re}"
        if [ $exit_code -eq 0 ]; then
            local end_time=$(date +%s)
            local runtime=$((end_time - start_time))
            log "✓ icoFoam completed in ${runtime} seconds"
            
            # Validate results
            if validate_results "." "${re}"; then
                local status="SUCCESS"
                local final_time=$(ls -1 . | grep -E '^[0-9]+\.?[0-9]*$' | sort -n | tail -1)
                success_count=$((success_count + 1))
                log "✓ Case Re=${re} completed successfully"
            else
                local status="INVALID"
                local final_time="N/A"
                log "⚠ Case Re=${re} completed but results invalid"
            fi
        else
            local status="FAILED"
            local runtime="N/A"
            local final_time="N/A"
            log "ERROR: icoFoam failed or timed out for Re=${re}"
            echo "icoFoam log (last 10 lines):"
            tail -10 log.icoFoam
        fi
        
        # Record results
        echo "${re},${status},${runtime},${final_time},${case_dir}" >> "${summary_file}"
        log "Recorded: Re=${re}, Status=${status}"
        
        log "=== Completed Re=${re} ==="
    done
    
    # Return to original directory
    cd "${WORKSPACE}"
    
    # Generate final summary
    echo ""
    log "=== PARAMETRIC STUDY COMPLETED ==="
    log "Total cases: ${total_count}"
    log "Successful cases: ${success_count}"
    
    if [ ${total_count} -gt 0 ]; then
        local success_rate=$(echo "scale=1; ${success_count}*100/${total_count}" | bc -l)
        log "Success rate: ${success_rate}%"
    fi
    
    log "Results summary:"
    if [ -f "${summary_file}" ]; then
        cat "${summary_file}"
    else
        log "ERROR: Summary file not created"
    fi
    
    log "Case directories created:"
    ls -la "${RESULTS_DIR}/" | grep "cavity_Re_" || log "No case directories found"
    
    log "Detailed log: ${LOG_FILE}"
    log "=== STUDY FINISHED SUCCESSFULLY ==="
}

# Improved error handling
trap 'echo "ERROR: Script failed at line $LINENO"; exit 1' ERR

# Execute main function
echo "Calling main function..."
main "$@"

echo ""
echo "=== SCRIPT COMPLETED ==="
echo "Check results in: ${RESULTS_DIR}"
echo "Check log file: ${LOG_FILE}"
exit 0
