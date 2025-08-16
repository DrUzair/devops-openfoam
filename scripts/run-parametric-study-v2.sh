#!/bin/bash
# Enhanced OpenFOAM Parametric Study Script for CI/CD Pipeline
# Supports parallel execution, robust error handling, and structured output

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# ============================================================================
# Configuration and Environment Setup
# ============================================================================

# Default values (can be overridden by environment variables)
REYNOLDS_NUMBERS="${REYNOLDS_NUMBERS:-100,500,1000}"
MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
RESULTS_DIR="${RESULTS_DIR:-./results}"
BENCHMARK_MODE="${BENCHMARK_MODE:-false}"
VALIDATION_TOLERANCE="${VALIDATION_TOLERANCE:-1e-6}"

# Script metadata
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="run-parametric-study.sh"
START_TIME=$(date +%s)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Logging functions
log_info() {
    echo "[INFO] $(date -u +%H:%M:%S) $*" >&2
}

log_error() {
    echo "[ERROR] $(date -u +%H:%M:%S) $*" >&2
}

log_warning() {
    echo "[WARN] $(date -u +%H:%M:%S) $*" >&2
}

# ============================================================================
# Validation and Setup Functions
# ============================================================================

validate_environment() {
    log_info "Validating OpenFOAM environment..."
    
    # Check if OpenFOAM is properly sourced
    if ! command -v blockMesh &> /dev/null; then
        log_error "OpenFOAM not found. Sourcing environment..."
        if [ -f "/opt/openfoam9/etc/bashrc" ]; then
            source /opt/openfoam9/etc/bashrc
        else
            log_error "OpenFOAM installation not found"
            exit 1
        fi
    fi
    
    # Verify required OpenFOAM utilities
    local required_utils=("blockMesh" "simpleFoam" "postProcess")
    for util in "${required_utils[@]}"; do
        if ! command -v "$util" &> /dev/null; then
            log_error "Required OpenFOAM utility not found: $util"
            exit 1
        fi
    done
    
    log_info "OpenFOAM environment validated successfully"
}

setup_directories() {
    log_info "Setting up directory structure..."
    
    # Create results directory with proper permissions
    mkdir -p "$RESULTS_DIR"
    chmod 755 "$RESULTS_DIR"
    
    # Create subdirectories for organization
    mkdir -p "$RESULTS_DIR/logs"
    mkdir -p "$RESULTS_DIR/plots"
    mkdir -p "$RESULTS_DIR/raw_data"
    
    log_info "Directory structure created: $RESULTS_DIR"
}

validate_case_files() {
    log_info "Validating OpenFOAM case files..."
    
    local required_dirs=("0" "constant" "system")
    local required_files=(
        "0/U"
        "0/p" 
        "constant/transportProperties"
        "system/controlDict"
        "system/fvSchemes"
        "system/fvSolution"
        "system/blockMeshDict"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Missing required directory: $dir"
            exit 1
        fi
    done
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Missing required file: $file"
            exit 1
        fi
    done
    
    log_info "Case files validation completed"
}

# ============================================================================
# Simulation Functions
# ============================================================================

calculate_viscosity() {
    local reynolds=$1
    local velocity=1.0  # m/s
    local length=1.0    # m (cavity size)
    
    # nu = U * L / Re
    echo "$velocity * $length / $reynolds" | bc -l
}

prepare_case() {
    local reynolds=$1
    local case_dir="Re_$reynolds"
    
    log_info "Preparing case for Re = $reynolds"
    
    # Clean and create case directory
    rm -rf "$case_dir"
    cp -r . "$case_dir"
    cd "$case_dir"
    
    # Calculate kinematic viscosity
    local viscosity
    viscosity=$(calculate_viscosity "$reynolds")
    
    # Update transportProperties
    cat > constant/transportProperties << EOF
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      transportProperties;
}

nu              nu [0 2 -1 0 0 0 0] $viscosity;
EOF

    # Update controlDict with convergence criteria
    cat > system/controlDict << EOF
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      controlDict;
}

application     simpleFoam;
startFrom       startTime;
startTime       0;
stopAt          endTime;
endTime         ${MAX_ITERATIONS};
deltaT          1;
writeControl    timeStep;
writeInterval   50;
purgeWrite      2;
writeFormat     ascii;
writePrecision  8;
writeCompression off;
timeFormat      general;
timePrecision   6;
runTimeModifiable true;

// Convergence criteria
residualControl
{
    p               ${VALIDATION_TOLERANCE};
    U               ${VALIDATION_TOLERANCE};
}
EOF

    log_info "Case prepared for Re = $reynolds (viscosity = $viscosity)"
    cd ..
}

run_simulation() {
    local reynolds=$1
    local case_dir="Re_$reynolds"
    
    log_info "Running simulation for Re = $reynolds"
    
    cd "$case_dir"
    
    # Capture start time for this simulation
    local sim_start=$(date +%s)
    
    # Initialize log files
    local log_file="../$RESULTS_DIR/logs/Re_${reynolds}.log"
    echo "OpenFOAM Simulation Log - Re = $reynolds" > "$log_file"
    echo "Started: $(date)" >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
    
    # Generate mesh
    log_info "Generating mesh for Re = $reynolds"
    if ! blockMesh >> "$log_file" 2>&1; then
        log_error "blockMesh failed for Re = $reynolds"
        cd ..
        return 1
    fi
    
    # Check mesh quality
    if ! checkMesh >> "$log_file" 2>&1; then
        log_warning "Mesh quality issues detected for Re = $reynolds"
    fi
    
    # Run solver
    log_info "Running solver for Re = $reynolds"
    if ! simpleFoam >> "$log_file" 2>&1; then
        log_error "simpleFoam failed for Re = $reynolds"
        cd ..
        return 1
    fi
    
    # Check convergence
    if check_convergence "$log_file"; then
        echo "CONVERGED" > converged.log
        log_info "Simulation converged for Re = $reynolds"
    else
        echo "NOT_CONVERGED" > converged.log
        log_warning "Simulation did not converge for Re = $reynolds"
    fi
    
    # Post-processing
    log_info "Running post-processing for Re = $reynolds"
    if ! run_postprocessing "$reynolds" "$log_file"; then
        log_warning "Post-processing issues for Re = $reynolds"
    fi
    
    # Calculate simulation time
    local sim_end=$(date +%s)
    local sim_duration=$((sim_end - sim_start))
    
    echo "Simulation completed in ${sim_duration}s" >> "$log_file"
    
    cd ..
    log_info "Simulation completed for Re = $reynolds"
    
    return 0
}

check_convergence() {
    local log_file=$1
    
    # Check if residuals dropped below tolerance
    local final_p_residual final_u_residual
    
    final_p_residual=$(tail -100 "$log_file" | grep -E "Solving for p" | tail -1 | awk '{print $(NF-1)}' | tr -d ',')
    final_u_residual=$(tail -100 "$log_file" | grep -E "Solving for Ux" | tail -1 | awk '{print $(NF-1)}' | tr -d ',')
    
    if [[ -n "$final_p_residual" && -n "$final_u_residual" ]]; then
        # Use Python for floating point comparison
        python3 -c "
import sys
p_res = float('$final_p_residual') if '$final_p_residual' else 1.0
u_res = float('$final_u_residual') if '$final_u_residual' else 1.0
tol = float('$VALIDATION_TOLERANCE')
sys.exit(0 if (p_res < tol and u_res < tol) else 1)
        "
    else
        return 1
    fi
}

run_postprocessing() {
    local reynolds=$1
    local log_file=$2
    
    # Create post-processing directory
    mkdir -p postProcessing
    
    # Sample velocity along centerlines
    postProcess -func "
        sets
        {
            type sets;
            libs (sampling);
            writeControl writeTime;
            
            sets
            (
                centerlineX
                {
                    type    uniform;
                    axis    y;
                    start   (0.5 0 0.5);
                    end     (0.5 1 0.5);
                    nPoints 100;
                }
                
                centerlineY
                {
                    type    uniform;
                    axis    x;
                    start   (0 0.5 0.5);
                    end     (1 0.5 0.5);
                    nPoints 100;
                }
            );
        }
    " >> "$log_file" 2>&1
    
    # Calculate flow statistics
    postProcess -func "
        flowRatePatch
        {
            type    flowRatePatch;
            libs    (fieldFunctionObjects);
            patches (movingWall);
        }
    " >> "$log_file" 2>&1
    
    # Copy results to main results directory
    if [ -d "postProcessing" ]; then
        cp -r postProcessing "../$RESULTS_DIR/raw_data/Re_${reynolds}_postProcessing"
    fi
    
    return 0
}

# ============================================================================
# Parallel Execution and Job Management
# ============================================================================

run_parallel_simulations() {
    local reynolds_array=($1)
    local total_cases=${#reynolds_array[@]}
    
    log_info "Starting parallel execution of $total_cases cases with $PARALLEL_JOBS jobs"
    
    # Create job queue
    local job_queue="$RESULTS_DIR/job_queue.txt"
    printf '%s\n' "${reynolds_array[@]}" > "$job_queue"
    
    # Export functions for parallel execution
    export -f run_simulation
    export -f prepare_case
    export -f check_convergence
    export -f run_postprocessing
    export -f calculate_viscosity
    export -f log_info
    export -f log_error
    export -f log_warning
    
    # Export variables
    export MAX_ITERATIONS VALIDATION_TOLERANCE RESULTS_DIR
    
    # Run simulations in parallel
    if command -v parallel &> /dev/null; then
        log_info "Using GNU parallel for job execution"
        cat "$job_queue" | parallel -j "$PARALLEL_JOBS" --progress run_single_case {}
    else
        log_info "GNU parallel not available, using bash background jobs"
        run_bash_parallel "$job_queue"
    fi
    
    # Wait for all background jobs to complete
    wait
    
    log_info "All parallel simulations completed"
}

run_single_case() {
    local reynolds=$1
    
    # Prepare and run simulation
    prepare_case "$reynolds"
    
    if run_simulation "$reynolds"; then
        log_info "Successfully completed Re = $reynolds"
        return 0
    else
        log_error "Failed simulation for Re = $reynolds"
        return 1
    fi
}

run_bash_parallel() {
    local job_queue=$1
    local active_jobs=0
    
    while IFS= read -r reynolds || [ $active_jobs -gt 0 ]; do
        # Wait if we've reached the parallel job limit
        while [ $active_jobs -ge "$PARALLEL_JOBS" ]; do
            wait -n  # Wait for any background job to complete
            active_jobs=$((active_jobs - 1))
        done
        
        # Start new job if we have more work
        if [ -n "$reynolds" ]; then
            run_single_case "$reynolds" &
            active_jobs=$((active_jobs + 1))
        fi
    done < "$job_queue"
}

# ============================================================================
# Results Processing and Analysis
# ============================================================================

generate_summary_report() {
    log_info "Generating summary report..."
    
    local summary_file="$RESULTS_DIR/summary_report.json"
    local reynolds_array=($1)
    
    # Start JSON report
    cat > "$summary_file" << EOF
{
    "metadata": {
        "script_version": "$SCRIPT_VERSION",
        "timestamp": "$TIMESTAMP",
        "total_runtime_seconds": $(($(date +%s) - START_TIME)),
        "openfoam_version": "${WM_PROJECT_VERSION:-unknown}",
        "parameters": {
            "reynolds_numbers": "$(echo "${reynolds_array[@]}" | tr ' ' ',')",
            "max_iterations": $MAX_ITERATIONS,
            "parallel_jobs": $PARALLEL_JOBS,
            "validation_tolerance": $VALIDATION_TOLERANCE
        }
    },
    "results": [
EOF

    local first=true
    for reynolds in "${reynolds_array[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "        ," >> "$summary_file"
        fi
        
        generate_case_summary "$reynolds" >> "$summary_file"
    done
    
    cat >> "$summary_file" << EOF
    ],
    "overall_status": "$(calculate_overall_status "${reynolds_array[@]}")"
}
EOF

    log_info "Summary report generated: $summary_file"
}

generate_case_summary() {
    local reynolds=$1
    local case_dir="Re_$reynolds"
    
    # Default values
    local status="FAILED"
    local converged="false"
    local iterations=0
    local final_residual_p="N/A"
    local final_residual_u="N/A"
    
    # Check if case exists and get details
    if [ -d "$case_dir" ]; then
        if [ -f "$case_dir/converged.log" ]; then
            local conv_status
            conv_status=$(cat "$case_dir/converged.log")
            if [ "$conv_status" = "CONVERGED" ]; then
                status="SUCCESS"
                converged="true"
            else
                status="COMPLETED_NO_CONVERGENCE"
            fi
        fi
        
        # Extract iteration count
        if [ -f "$RESULTS_DIR/logs/Re_${reynolds}.log" ]; then
            iterations=$(grep -c "Time = " "$RESULTS_DIR/logs/Re_${reynolds}.log" || echo "0")
            
            # Extract final residuals
            final_residual_p=$(tail -100 "$RESULTS_DIR/logs/Re_${reynolds}.log" | grep -E "Solving for p" | tail -1 | awk '{print $(NF-1)}' | tr -d ',' || echo "N/A")
            final_residual_u=$(tail -100 "$RESULTS_DIR/logs/Re_${reynolds}.log" | grep -E "Solving for Ux" | tail -1 | awk '{print $(NF-1)}' | tr -d ',' || echo "N/A")
        fi
    fi
    
    cat << EOF
        {
            "reynolds_number": $reynolds,
            "status": "$status",
            "converged": $converged,
            "iterations_completed": $iterations,
            "final_residuals": {
                "pressure": "$final_residual_p",
                "velocity": "$final_residual_u"
            },
            "case_directory": "$case_dir",
            "log_file": "logs/Re_${reynolds}.log"
        }
EOF
}

calculate_overall_status() {
    local reynolds_array=("$@")
    local success_count=0
    local total_count=${#reynolds_array[@]}
    
    for reynolds in "${reynolds_array[@]}"; do
        if [ -f "Re_$reynolds/converged.log" ]; then
            local conv_status
            conv_status=$(cat "Re_$reynolds/converged.log")
            if [ "$conv_status" = "CONVERGED" ]; then
                success_count=$((success_count + 1))
            fi
        fi
    done
    
    if [ $success_count -eq $total_count ]; then
        echo "ALL_SUCCESS"
    elif [ $success_count -gt 0 ]; then
        echo "PARTIAL_SUCCESS"
    else
        echo "ALL_FAILED"
    fi
}

create_visualization_plots() {
    log_info "Creating visualization plots..."
    
    # Create Python script for plotting
    cat > "$RESULTS_DIR/generate_plots.py" << 'EOF'
import os
import sys
import json
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

def load_summary_data(results_dir):
    summary_file = os.path.join(results_dir, 'summary_report.json')
    if not os.path.exists(summary_file):
        print(f"Summary file not found: {summary_file}")
        return None
    
    with open(summary_file, 'r') as f:
        return json.load(f)

def create_convergence_plot(data, results_dir):
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8))
    
    reynolds_nums = []
    iterations = []
    p_residuals = []
    u_residuals = []
    
    for result in data['results']:
        if result['status'] in ['SUCCESS', 'COMPLETED_NO_CONVERGENCE']:
            reynolds_nums.append(result['reynolds_number'])
            iterations.append(result['iterations_completed'])
            
            try:
                p_res = float(result['final_residuals']['pressure'])
                u_res = float(result['final_residuals']['velocity'])
                p_residuals.append(p_res)
                u_residuals.append(u_res)
            except (ValueError, TypeError):
                p_residuals.append(1e-3)
                u_residuals.append(1e-3)
    
    # Plot iterations vs Reynolds number
    ax1.bar(reynolds_nums, iterations, alpha=0.7, color='skyblue')
    ax1.set_xlabel('Reynolds Number')
    ax1.set_ylabel('Iterations to Convergence')
    ax1.set_title('Convergence Performance by Reynolds Number')
    ax1.grid(True, alpha=0.3)
    
    # Plot final residuals
    x_pos = np.arange(len(reynolds_nums))
    width = 0.35
    
    ax2.bar(x_pos - width/2, p_residuals, width, label='Pressure', alpha=0.7)
    ax2.bar(x_pos + width/2, u_residuals, width, label='Velocity', alpha=0.7)
    ax2.set_xlabel('Reynolds Number')
    ax2.set_ylabel('Final Residual')
    ax2.set_title('Final Residuals by Reynolds Number')
    ax2.set_yscale('log')
    ax2.set_xticks(x_pos)
    ax2.set_xticklabels(reynolds_nums)
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(results_dir, 'plots', 'convergence_analysis.png'), dpi=300, bbox_inches='tight')
    plt.close()

def create_status_summary(data, results_dir):
    fig, ax = plt.subplots(figsize=(8, 6))
    
    status_counts = {}
    for result in data['results']:
        status = result['status']
        status_counts[status] = status_counts.get(status, 0) + 1
    
    colors = {'SUCCESS': 'green', 'COMPLETED_NO_CONVERGENCE': 'orange', 'FAILED': 'red'}
    labels = list(status_counts.keys())
    sizes = list(status_counts.values())
    plot_colors = [colors.get(label, 'gray') for label in labels]
    
    ax.pie(sizes, labels=labels, colors=plot_colors, autopct='%1.1f%%', startangle=90)
    ax.set_title('Simulation Results Summary')
    
    plt.savefig(os.path.join(results_dir, 'plots', 'results_summary.png'), dpi=300, bbox_inches='tight')
    plt.close()

if __name__ == "__main__":
    results_dir = sys.argv[1] if len(sys.argv) > 1 else "./results"
    
    # Load data
    data = load_summary_data(results_dir)
    if data is None:
        sys.exit(1)
    
    # Create plots directory
    plots_dir = os.path.join(results_dir, 'plots')
    os.makedirs(plots_dir, exist_ok=True)
    
    # Generate plots
    create_convergence_plot(data, results_dir)
    create_status_summary(data, results_dir)
    
    print(f"Plots generated in: {plots_dir}")
EOF

    # Run the plotting script
    if command -v python3 &> /dev/null; then
        python3 "$RESULTS_DIR/generate_plots.py" "$RESULTS_DIR"
    else
        log_warning "Python3 not available for plot generation"
    fi
}

# ============================================================================
# Cleanup and Error Handling
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script terminated with exit code: $exit_code"
    fi
    
    # Clean up temporary files
    rm -f "$RESULTS_DIR/job_queue.txt"
    
    # Archive logs if in benchmark mode
    if [ "$BENCHMARK_MODE" = "true" ]; then
        tar -czf "$RESULTS_DIR/simulation_logs.tar.gz" "$RESULTS_DIR/logs/" 2>/dev/null || true
    fi
    
    log_info "Cleanup completed"
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

# ============================================================================
# Main Execution Flow
# ============================================================================

main() {
    log_info "Starting OpenFOAM parametric study v$SCRIPT_VERSION"
    log_info "Parameters: Re=[${REYNOLDS_NUMBERS}], MaxIter=${MAX_ITERATIONS}, Jobs=${PARALLEL_JOBS}"
    
    # Convert comma-separated Reynolds numbers to array
    IFS=',' read -ra REYNOLDS_ARRAY <<< "$REYNOLDS_NUMBERS"
    
    # Validation and setup
    validate_environment
    setup_directories
    validate_case_files
    
    # Run simulations
    run_parallel_simulations "${REYNOLDS_ARRAY[*]}"
    
    # Generate results and reports
    generate_summary_report "${REYNOLDS_ARRAY[*]}"
    create_visualization_plots
    
    # Final status report
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    log_info "Parametric study completed successfully"
    log_info "Total execution time: ${total_duration}s ($(echo "scale=1; $total_duration/60" | bc)m)"
    log_info "Results available in: $RESULTS_DIR"
    
    # Print summary
    echo ""
    echo "============================================================================"
    echo "OpenFOAM Parametric Study Summary"
    echo "============================================================================"
    echo "Reynolds Numbers: ${REYNOLDS_NUMBERS}"
    echo "Total Cases: ${#REYNOLDS_ARRAY[@]}"
    echo "Parallel Jobs: ${PARALLEL_JOBS}"
    echo "Execution Time: ${total_duration}s"
    echo "Results Directory: ${RESULTS_DIR}"
    echo "============================================================================"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi