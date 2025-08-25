#!/bin/bash

# Utility functions for Oracle Instance Creator scripts
# Common functions for logging, error handling, and validation

set -euo pipefail

# Colors for logging (if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# Logging functions
log_info() {
    echo "${BLUE}[INFO]${RESET} $*" >&2
}

log_success() {
    echo "${GREEN}[SUCCESS]${RESET} $*" >&2
}

log_warning() {
    echo "${YELLOW}[WARNING]${RESET} $*" >&2
}

log_error() {
    echo "${RED}[ERROR]${RESET} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "${BOLD}[DEBUG]${RESET} $*" >&2
    fi
}

# Timing functions for performance monitoring
declare -A TIMER_START_TIMES

start_timer() {
    local timer_name="$1"
    TIMER_START_TIMES[$timer_name]=$(date +%s.%N)
    log_debug "Started timer: $timer_name"
}

log_elapsed() {
    local timer_name="$1"
    local start_time="${TIMER_START_TIMES[$timer_name]:-}"
    
    if [[ -n "$start_time" ]]; then
        local end_time=$(date +%s.%N)
        local elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        log_info "Timer '$timer_name' elapsed: ${elapsed}s"
        unset TIMER_START_TIMES[$timer_name]
    else
        log_warning "Timer '$timer_name' was not started"
    fi
}

# Error handling
die() {
    log_error "$*"
    exit 1
}

# Environment variable validation
require_env_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    
    if [[ -z "$var_value" ]]; then
        die "Required environment variable $var_name is not set"
    fi
}

# Validate environment variable with default
get_env_var_or_default() {
    local var_name="$1"
    local default_value="$2"
    local var_value="${!var_name:-$default_value}"
    
    echo "$var_value"
}

# OCI CLI command wrapper for data extraction (no debug pollution)
oci_cmd_data() {
    local cmd=("$@")
    local output
    local status
    
    log_debug "Executing OCI data command: oci ${cmd[*]}"
    
    set +e
    output=$(oci "${cmd[@]}" 2>&1)
    status=$?
    set -e
    
    if [[ $status -ne 0 ]]; then
        log_error "OCI data command failed with status $status"
        log_error "Command: ${cmd[*]}"
        log_error "Output: $output"
        return $status
    fi
    
    echo "$output"
}

# OCI CLI command wrapper with debug support (for troubleshooting)
oci_cmd_debug() {
    local cmd=("$@")
    local output
    local status
    local oci_args=()
    
    # Add debug flag if DEBUG is enabled
    if [[ "${DEBUG:-}" == "true" ]]; then
        oci_args+=("--debug")
    fi
    
    log_debug "Executing OCI debug command: oci ${oci_args[*]} ${cmd[*]}"
    
    set +e
    output=$(oci "${oci_args[@]}" "${cmd[@]}" 2>&1)
    status=$?
    set -e
    
    if [[ $status -ne 0 ]]; then
        log_error "OCI debug command failed with status $status"
        log_error "Command: ${cmd[*]}"
        log_error "Output: $output"
        return $status
    fi
    
    echo "$output"
}

# Intelligent OCI CLI command wrapper - uses appropriate mode
oci_cmd() {
    local cmd=("$@")
    
    # Check if this is a data extraction command (contains --query or --raw-output)
    local is_data_query=false
    for arg in "${cmd[@]}"; do
        if [[ "$arg" == "--query" || "$arg" == "--raw-output" ]]; then
            is_data_query=true
            break
        fi
    done
    
    # Use data mode for queries to avoid debug pollution, debug mode for actions
    if [[ "$is_data_query" == "true" ]]; then
        oci_cmd_data "${cmd[@]}"
    else
        oci_cmd_debug "${cmd[@]}"
    fi
}

# Check if OCI CLI is available
check_oci_cli() {
    if ! command -v oci >/dev/null 2>&1; then
        die "OCI CLI is not installed or not in PATH"
    fi
    
    log_debug "OCI CLI found: $(which oci)"
}

# Extract error type from OCI output
get_error_type() {
    local error_output="$1"
    
    if echo "$error_output" | grep -qi "capacity\|host capacity\|out of capacity\|service limit\|quota exceeded\|resource unavailable\|insufficient capacity"; then
        log_debug "Detected CAPACITY error pattern in: $error_output"
        echo "CAPACITY"
    elif echo "$error_output" | grep -qi "too many requests\|rate limit\|throttle\|429"; then
        log_debug "Detected RATE_LIMIT error pattern in: $error_output"
        echo "CAPACITY"  # Treat rate limiting as capacity issue
    elif echo "$error_output" | grep -qi "display name already exists\|instance.*already exists\|duplicate.*name"; then
        log_debug "Detected DUPLICATE error pattern in: $error_output"
        echo "DUPLICATE"  # Instance already exists - treat as success
    elif echo "$error_output" | grep -qi "authentication\|authorization\|unauthorized"; then
        echo "AUTH"
    elif echo "$error_output" | grep -qi "network\|timeout\|connection"; then
        echo "NETWORK"
    elif echo "$error_output" | grep -qi "not found\|invalid.*id\|does not exist"; then
        echo "CONFIG"
    else
        echo "UNKNOWN"
    fi
}

# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local cmd=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}"
        
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "Command failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Validate OCID format
is_valid_ocid() {
    local ocid="$1"
    if [[ "$ocid" =~ ^ocid1\.[a-z0-9]+\.[a-z0-9-]*\.[a-z0-9-]*\..+ ]]; then
        return 0
    else
        return 1
    fi
}