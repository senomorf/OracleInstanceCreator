#!/bin/bash

# Parallel OCI instance launcher script
# Attempts to create both free tier shapes simultaneously:
# - VM.Standard.A1.Flex (ARM): 4 OCPUs, 24GB RAM
# - VM.Standard.E2.1.Micro (AMD): 1 OCPU, 1GB RAM

set -euo pipefail

source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/notify.sh"

# Global variables for signal handling
PID_A1=""
PID_E2=""
temp_dir=""

# Signal handler for graceful shutdown
cleanup_handler() {
    log_warning "Received interrupt signal - cleaning up background processes"
    
    if [[ -n "$PID_A1" ]]; then
        log_debug "Terminating A1 process (PID: $PID_A1)"
        kill $PID_A1 2>/dev/null || true
    fi
    
    if [[ -n "$PID_E2" ]]; then
        log_debug "Terminating E2 process (PID: $PID_E2)"
        kill $PID_E2 2>/dev/null || true
    fi
    
    sleep $GRACEFUL_TERMINATION_DELAY
    
    # Force kill if still running
    [[ -n "$PID_A1" ]] && kill -9 $PID_A1 2>/dev/null || true
    [[ -n "$PID_E2" ]] && kill -9 $PID_E2 2>/dev/null || true
    
    # Cleanup temporary files
    [[ -n "$temp_dir" && -d "$temp_dir" ]] && rm -rf "$temp_dir" 2>/dev/null || true
    
    log_info "Cleanup completed"
    exit $OCI_EXIT_GENERAL_ERROR
}

# Set up signal handlers
trap cleanup_handler SIGTERM SIGINT

# Shape configurations for Oracle Cloud free tier
declare -A A1_FLEX_CONFIG=(
    ["SHAPE"]="VM.Standard.A1.Flex"
    ["OCPUS"]="4"
    ["MEMORY_IN_GBS"]="24"
    ["DISPLAY_NAME"]="a1-flex-sg"
)

declare -A E2_MICRO_CONFIG=(
    ["SHAPE"]="VM.Standard.E2.1.Micro"
    ["OCPUS"]=""
    ["MEMORY_IN_GBS"]=""
    ["DISPLAY_NAME"]="e2-micro-sg"
)

launch_shape() {
    local shape_name="$1"
    local -n config=$2
    
    log_info "Starting $shape_name launch attempt..."
    
    # Set shape-specific environment variables
    export OCI_SHAPE="${config[SHAPE]}"
    export OCI_OCPUS="${config[OCPUS]}"
    export OCI_MEMORY_IN_GBS="${config[MEMORY_IN_GBS]}"
    export INSTANCE_DISPLAY_NAME="${config[DISPLAY_NAME]}"
    
    # Launch the instance using existing script
    local script_dir
    script_dir="$(dirname "$0")"
    "$script_dir/launch-instance.sh"
    
    return $?
}

# Main parallel execution
main() {
    start_timer "parallel_execution"
    log_info "Starting parallel OCI instance creation for both free tier shapes"
    
    # Set timeout to prevent exceeding 60 seconds (GitHub Actions billing boundary)
    # Using constant defined in utils.sh for consistency and maintainability
    local timeout_seconds=$GITHUB_ACTIONS_TIMEOUT_SECONDS
    log_debug "Setting execution timeout to ${timeout_seconds}s to avoid 2-minute billing"
    
    # Create temporary files for process communication with secure permissions  
    umask 077  # Ensure secure permissions (owner only)
    temp_dir=$(mktemp -d)  # Using global variable for cleanup handler
    log_debug "Created secure temporary directory: $temp_dir"
    local a1_result="${temp_dir}/a1_result"
    local e2_result="${temp_dir}/e2_result"
    
    # Launch A1.Flex in background
    log_info "Launching A1.Flex (ARM) instance in background..."
    (
        launch_shape "A1.Flex" A1_FLEX_CONFIG
        local exit_code=$?
        echo "$exit_code" > "$a1_result"
        exit $exit_code
    ) &
    PID_A1=$!
    
    # Launch E2.Micro in background  
    log_info "Launching E2.1.Micro (AMD) instance in background..."
    (
        launch_shape "E2.1.Micro" E2_MICRO_CONFIG
        local exit_code=$?
        echo "$exit_code" > "$e2_result"
        exit $exit_code
    ) &
    PID_E2=$!
    
    # Wait for both processes to complete with timeout
    log_info "Waiting for both shape attempts to complete (timeout: ${timeout_seconds}s)..."
    
    # Initialize status variables
    local STATUS_A1=1
    local STATUS_E2=1
    
    # Wait for both processes with timeout protection
    local elapsed=0
    local sleep_interval=1  # Monitor processes every second during execution
    
    # Keep checking until timeout or both processes complete
    while [[ $elapsed -lt $timeout_seconds ]]; do
        # Check if both processes have finished
        if ! kill -0 $PID_A1 2>/dev/null && ! kill -0 $PID_E2 2>/dev/null; then
            log_debug "Both processes completed after ${elapsed}s"
            break
        fi
        sleep $sleep_interval
        ((elapsed += sleep_interval))
    done
    
    # Handle timeout case
    if [[ $elapsed -ge $timeout_seconds ]]; then
        log_warning "Execution timeout reached (${timeout_seconds}s) - terminating background processes"
        kill $PID_A1 $PID_E2 2>/dev/null || true
        sleep $GRACEFUL_TERMINATION_DELAY  # Give processes time to terminate gracefully before force kill
        kill -9 $PID_A1 $PID_E2 2>/dev/null || true
        STATUS_A1=$TIMEOUT_EXIT_CODE  # Standard timeout exit code (GNU timeout compatibility)
        STATUS_E2=$TIMEOUT_EXIT_CODE  # Standard timeout exit code (GNU timeout compatibility)
    fi
    
    # Always wait for processes to fully complete and flush their output
    wait $PID_A1 2>/dev/null || true
    wait $PID_E2 2>/dev/null || true
    
    # Wait for result files with proper timeout (fixes race condition)
    if wait_for_result_file "$a1_result"; then
        STATUS_A1=$(cat "$a1_result")
        log_debug "A1 result file found with status: $STATUS_A1"
    else
        log_warning "A1 result file not found - using default failure status"
    fi
    
    if wait_for_result_file "$e2_result"; then
        STATUS_E2=$(cat "$e2_result")
        log_debug "E2 result file found with status: $STATUS_E2"
    else
        log_warning "E2 result file not found - using default failure status"
    fi
    
    # Cleanup temporary files
    rm -rf "$temp_dir" 2>/dev/null || true
    
    # Log results
    if [[ $STATUS_A1 -eq 0 ]]; then
        log_success "A1.Flex (ARM) instance creation: SUCCESS"
    elif [[ $STATUS_A1 -eq 124 ]]; then
        log_warning "A1.Flex (ARM) instance creation: TIMEOUT"
    else
        log_warning "A1.Flex (ARM) instance creation: FAILED"
    fi
    
    if [[ $STATUS_E2 -eq 0 ]]; then
        log_success "E2.1.Micro (AMD) instance creation: SUCCESS" 
    elif [[ $STATUS_E2 -eq 124 ]]; then
        log_warning "E2.1.Micro (AMD) instance creation: TIMEOUT"
    else
        log_warning "E2.1.Micro (AMD) instance creation: FAILED"
    fi
    
    # Determine overall result
    local success_count=0
    [[ $STATUS_A1 -eq 0 ]] && success_count=$((success_count + 1))
    [[ $STATUS_E2 -eq 0 ]] && success_count=$((success_count + 1))
    
    log_elapsed "parallel_execution"
    
    if [[ $success_count -gt 0 ]]; then
        log_success "Parallel execution completed: $success_count of 2 instances created successfully"
        
        # Send combined success notification if notifications enabled
        if [[ "${ENABLE_NOTIFICATIONS:-}" == "true" ]]; then
            local shapes_created=""
            [[ $STATUS_A1 -eq 0 ]] && shapes_created="A1.Flex (ARM)"
            [[ $STATUS_E2 -eq 0 ]] && shapes_created="${shapes_created:+$shapes_created, }E2.1.Micro (AMD)"
            
            send_telegram_notification "success" "OCI instances created: $shapes_created"
        fi
        
        return 0
    else
        log_error "Parallel execution failed: Both instance creation attempts failed"
        
        # Let individual shape failures handle their own error notifications
        # This prevents duplicate error notifications
        
        return 1
    fi
}

# Execute main function if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi