#!/bin/bash

# Parallel OCI instance launcher script
# Attempts to create both free tier shapes simultaneously:
# - VM.Standard.A1.Flex (ARM): 4 OCPUs, 24GB RAM
# - VM.Standard.E2.1.Micro (AMD): 1 OCPU, 1GB RAM

set -euo pipefail

# shellcheck source=scripts/utils.sh
source "$(dirname "$0")/utils.sh"
# shellcheck source=scripts/notify.sh
source "$(dirname "$0")/notify.sh"

# Global variables for signal handling
PID_A1=""
PID_E2=""
temp_dir=""

# Performance monitoring functions
get_memory_usage() {
    if command -v free >/dev/null 2>&1; then
        # Linux - get used memory in MB
        free -m | awk 'NR==2{printf "%.1f", $3}'
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS - get used memory in MB
        vm_stat | awk '
        /Pages free/ { free = $3 + 0 }
        /Pages active/ { active = $3 + 0 }
        /Pages inactive/ { inactive = $3 + 0 }
        /Pages wired down/ { wired = $4 + 0 }
        END { printf "%.1f", (active + inactive + wired) * 4096 / 1024 / 1024 }'
    else
        echo "0"
    fi
}

# Track resource contention during parallel execution
track_resource_usage() {
    local phase="$1" # "start", "peak", "end"
    local memory_usage
    memory_usage=$(get_memory_usage)

    # Log resource usage for monitoring
    log_performance_metric "RESOURCE_USAGE" "parallel_execution" "$phase" "1" "Memory=${memory_usage}MB"

    # Store peak usage for analysis
    if [[ "$phase" == "peak" ]]; then
        echo "$memory_usage" >"${temp_dir}/peak_memory_usage" 2>/dev/null || true
    fi
}

# Terminate background processes gracefully then forcefully
terminate_processes() {
    # Graceful termination first
    if [[ -n "$PID_A1" ]] && kill -0 "$PID_A1" 2>/dev/null; then
        log_debug "Terminating A1 process (PID: $PID_A1)"
        kill "$PID_A1" 2>/dev/null || true
    fi
    if [[ -n "$PID_E2" ]] && kill -0 "$PID_E2" 2>/dev/null; then
        log_debug "Terminating E2 process (PID: $PID_E2)"
        kill "$PID_E2" 2>/dev/null || true
    fi
    sleep "$GRACEFUL_TERMINATION_DELAY" # 2-second grace period allows processes to cleanup before SIGKILL

    # Force kill if still running
    if [[ -n "$PID_A1" ]] && kill -0 "$PID_A1" 2>/dev/null; then
        kill -9 "$PID_A1" 2>/dev/null || true
    fi
    if [[ -n "$PID_E2" ]] && kill -0 "$PID_E2" 2>/dev/null; then
        kill -9 "$PID_E2" 2>/dev/null || true
    fi
}

# Signal handler for graceful shutdown
cleanup_handler() {
    log_warning "Received interrupt signal - cleaning up background processes"

    terminate_processes

    # Cleanup temporary files
    if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        rm -rf "$temp_dir" 2>/dev/null || true
    fi

    log_info "Cleanup completed"
    exit "$OCI_EXIT_GENERAL_ERROR"
}

# Set up signal handlers
trap cleanup_handler SIGTERM SIGINT

# Shape configurations for Oracle Cloud free tier
# shellcheck disable=SC2034  # Used via nameref in launch_shape()
declare -A A1_FLEX_CONFIG=(
    ["SHAPE"]="VM.Standard.A1.Flex"
    ["OCPUS"]="4"
    ["MEMORY_IN_GBS"]="24"
    ["DISPLAY_NAME"]="a1-flex-sg"
)

# shellcheck disable=SC2034  # Used via nameref in launch_shape()
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

    # Track shape-specific timing
    local shape_start_time
    shape_start_time=$(date +%s)

    # Set shape-specific environment variables
    export OCI_SHAPE="${config[SHAPE]}"
    export OCI_OCPUS="${config[OCPUS]}"
    export OCI_MEMORY_IN_GBS="${config[MEMORY_IN_GBS]}"
    export INSTANCE_DISPLAY_NAME="${config[DISPLAY_NAME]}"

    # Launch the instance using existing script
    local script_dir
    script_dir="$(dirname "$0")"
    "$script_dir/launch-instance.sh"
    local exit_code=$?

    # Calculate and log shape execution time
    local shape_end_time duration
    shape_end_time=$(date +%s)
    duration=$((shape_end_time - shape_start_time))

    # Log shape performance metrics
    log_performance_metric "SHAPE_DURATION" "$shape_name" "$duration" "$exit_code" "Shape=${config[SHAPE]}"

    # Store duration for analysis (write to temp file if available)
    if [[ -n "${temp_dir:-}" ]]; then
        echo "$duration" >"${temp_dir}/${shape_name,,}_duration" 2>/dev/null || true
    fi

    return $exit_code
}

# Main parallel execution
main() {
    start_timer "parallel_execution"
    log_info "Starting parallel OCI instance creation for both free tier shapes"

    # Set timeout to prevent exceeding 60 seconds (GitHub Actions billing boundary)
    # Using constant defined in constants.sh for consistency and maintainability
    local timeout_seconds=$GITHUB_ACTIONS_BILLING_TIMEOUT
    log_debug "Setting execution timeout to ${timeout_seconds}s to avoid 2-minute billing"

    # Create temporary files for process communication with secure permissions
    umask 077             # Ensure secure permissions (owner only)
    temp_dir=$(mktemp -d) # Using global variable for cleanup handler
    chmod 700 "$temp_dir" # Explicit directory permissions
    log_debug "Created secure temporary directory: $temp_dir"
    local a1_result="${temp_dir}/a1_result"
    local e2_result="${temp_dir}/e2_result"

    # Pre-create result files with secure permissions
    touch "$a1_result" "$e2_result"
    chmod 600 "$a1_result" "$e2_result"

    # Track resource usage at start of parallel execution
    track_resource_usage "start"

    # Launch A1.Flex in background
    log_info "Launching A1.Flex (ARM) instance in background..."
    (
        launch_shape "A1.Flex" A1_FLEX_CONFIG
        local exit_code=$?
        echo "$exit_code" >"$a1_result"
        exit $exit_code
    ) &
    PID_A1=$!

    # Launch E2.Micro in background
    log_info "Launching E2.1.Micro (AMD) instance in background..."
    (
        launch_shape "E2.1.Micro" E2_MICRO_CONFIG
        local exit_code=$?
        echo "$exit_code" >"$e2_result"
        exit $exit_code
    ) &
    PID_E2=$!

    # Log concurrent execution start
    log_performance_metric "CONCURRENT_START" "parallel_execution" "1" "2" "A1_PID=$PID_A1,E2_PID=$PID_E2"

    # Wait for both processes to complete with timeout
    log_info "Waiting for both shape attempts to complete (timeout: ${timeout_seconds}s)..."

    # Initialize status variables
    local STATUS_A1=1
    local STATUS_E2=1

    # Wait for both processes with timeout protection
    local elapsed=0
    # Process monitoring interval - 1 second for responsive detection without excessive CPU usage
    local sleep_interval=1

    # Keep checking until timeout or both processes complete
    while [[ $elapsed -lt $timeout_seconds ]]; do
        # Check if both processes have finished
        if ! kill -0 $PID_A1 2>/dev/null && ! kill -0 $PID_E2 2>/dev/null; then
            log_debug "Both processes completed after ${elapsed}s"
            break
        fi

        # Track peak resource usage during execution (every 5 seconds to avoid overhead)
        if [[ $((elapsed % 5)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
            track_resource_usage "peak"
        fi

        sleep $sleep_interval
        ((elapsed += sleep_interval))
    done

    # Handle timeout case
    if [[ $elapsed -ge $timeout_seconds ]]; then
        log_warning "Execution timeout reached (${timeout_seconds}s) - terminating background processes"
        terminate_processes
        STATUS_A1=$EXIT_TIMEOUT_ERROR # Standard timeout exit code (GNU timeout compatibility)
        STATUS_E2=$EXIT_TIMEOUT_ERROR # Standard timeout exit code (GNU timeout compatibility)
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

    # Check if both failures are capacity-related (exit code 2 = OCI_EXIT_CAPACITY_ERROR)
    local capacity_failures=0
    [[ $STATUS_A1 -eq 2 ]] && capacity_failures=$((capacity_failures + 1))
    [[ $STATUS_E2 -eq 2 ]] && capacity_failures=$((capacity_failures + 1))

    log_elapsed "parallel_execution"

    # Track final resource usage and collect detailed performance summary
    track_resource_usage "end"

    # Collect shape-specific durations for analysis
    local a1_duration=0 e2_duration=0 peak_memory=0
    if [[ -f "${temp_dir}/a1.flex_duration" ]]; then
        a1_duration=$(cat "${temp_dir}/a1.flex_duration" 2>/dev/null || echo "0")
    fi
    if [[ -f "${temp_dir}/e2.1.micro_duration" ]]; then
        e2_duration=$(cat "${temp_dir}/e2.1.micro_duration" 2>/dev/null || echo "0")
    fi
    if [[ -f "${temp_dir}/peak_memory_usage" ]]; then
        peak_memory=$(cat "${temp_dir}/peak_memory_usage" 2>/dev/null || echo "0")
    fi

    # Log comprehensive execution summary
    local performance_summary="ExecutionTime=${elapsed}s,A1Duration=${a1_duration}s,E2Duration=${e2_duration}s"
    performance_summary="${performance_summary},PeakMemory=${peak_memory}MB,SuccessRate=${success_count}/2"
    log_performance_metric "CONCURRENT_END" "parallel_execution" "$success_count" "2" "$performance_summary"

    # Log structured performance data for analysis
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        local performance_context="{\"total_duration\":${elapsed},\"a1_duration\":${a1_duration}"
        performance_context="${performance_context},\"e2_duration\":${e2_duration},\"peak_memory\":${peak_memory}"
        performance_context="${performance_context},\"success_count\":${success_count},\"parallel_efficiency\":"
        performance_context+="$(((a1_duration + e2_duration) > 0 ? (a1_duration + e2_duration) * 100 / elapsed : 0))}"
        log_with_context "info" "Parallel execution performance summary" "$performance_context"
    fi

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
    elif [[ $capacity_failures -eq 2 ]]; then
        # Both failed due to capacity/limits - this is expected behavior, not an error
        log_info "Both shapes unavailable due to capacity/limits - will retry on next schedule"
        log_info "This is normal behavior when instance limits are reached or Oracle Cloud capacity is exhausted"

        # Send informational notification if enabled
        if [[ "${ENABLE_NOTIFICATIONS:-}" == "true" ]]; then
            send_telegram_notification "info" "OCI capacity/limits reached - both shapes unavailable, will retry later"
        fi

        return 0 # Don't treat capacity exhaustion as failure
    else
        log_error "Parallel execution failed: Instance creation failed due to configuration or authentication errors"

        # Let individual shape failures handle their own error notifications
        # This prevents duplicate error notifications

        return 1
    fi
}

# Execute main function if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
