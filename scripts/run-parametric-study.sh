#!/bin/bash

# OpenFOAM Parametric Study Automation
# Demonstrates advanced CI/CD and DevOps practices

set -euo pipefail

# Source OpenFOAM environment
source /opt/openfoam9/etc/bashrc

# Configuration
CASE_DIR="/opt/simulation/cases/cavity-flow"
RESULTS_DIR="/opt/simulation/results"
LOG_FILE="${RESULTS_DIR}/parametric-study.log"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Validation function
validate_results() {
    local case_dir=$1
    local reynolds=$2
    
    if [ ! -f "${case_dir}/postProcessing/residuals/0/residuals.dat" ]; then
        log "ERROR: Residuals file not found for Re=${reynolds}"
        return 1
    fi
    
    # Check convergence
    local final_residual=$(tail -1 "${case_dir}/postProcessing/residuals/0/residuals.dat" | awk '{print $2}')
    if (( $(echo "${final_residual} > 0.001" | bc -l) )); then
        log "WARNING: Poor convergence for Re=${reynolds}, residual=${final_residual}"
        return 1
    fi
    
    log "SUCCESS: Converged simulation for Re=${reynolds}"
    return 0
}

# Main parametric study
main() {
    log "Starting OpenFOAM parametric study"
    log "Container: $(hostname)"
    log "OpenFOAM version: $(echo $WM_PROJECT_VERSION)"
    
    # Reynolds numbers to study
    reynolds_numbers=(50 100 200 400 800)
    
    # Initialize summary
    echo "Reynolds,Status,Runtime,FinalResidual" > "${RESULTS_DIR}/summary.csv"
    
    for re in "${reynolds_numbers[@]}"; do
        log "Processing Reynolds number: ${re}"
        
        # Copy base case
        case_name="cavity-re-${re}"
        cp -r "${CASE_DIR}" "${RESULTS_DIR}/${case_name}"
        cd "${RESULTS_DIR}/${case_name}"
        
        # Update Reynolds number in transportProperties
        python3 - <<EOF
import sys
re_value = ${re}
nu_value = 1.0 / re_value

# Update transportProperties
with open('constant/transportProperties', 'r') as f:
    content = f.read()

content = content.replace('nu              [0 2 -1 0 0 0 0] 0.01;', 
                         f'nu              [0 2 -1 0 0 0 0] {nu_value:.6f};')

with open('constant/transportProperties', 'w') as f:
    f.write(content)

print(f"Updated nu = {nu_value:.6f} for Re = {re_value}")
EOF
        
        # Run simulation with timing
        start_time=$(date +%s)
        
        if blockMesh > log.blockMesh 2>&1 && \
           simpleFoam > log.simpleFoam 2>&1; then
            
            end_time=$(date +%s)
            runtime=$((end_time - start_time))
            
            if validate_results "." "${re}"; then
                status="SUCCESS"
                final_residual=$(tail -1 "postProcessing/residuals/0/residuals.dat" | awk '{print $2}')
            else
                status="CONVERGED_POOR"
                final_residual="N/A"
            fi
        else
            status="FAILED"
            runtime="N/A"
            final_residual="N/A"
            log "ERROR: Simulation failed for Re=${re}"
        fi
        
        # Record results
        echo "${re},${status},${runtime},${final_residual}" >> "${RESULTS_DIR}/summary.csv"
        
        # Generate plots for successful cases
        if [ "${status}" = "SUCCESS" ]; then
            python3 "${CASE_DIR}/../../../scripts/generate-plots.py" "${PWD}" "${re}"
        fi
        
        log "Completed Re=${re} with status=${status}"
    done
    
    # Generate final report
    log "Generating final report"
    python3 "/opt/simulation/scripts/generate-report.py" "${RESULTS_DIR}"
    
    log "Parametric study completed successfully"
    log "Results available in: ${RESULTS_DIR}"
}

# Error handling
trap 'log "ERROR: Script failed at line $LINENO"' ERR

# Execute main function
main "$@"