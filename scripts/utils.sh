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
    output=$(oci --no-retry --connection-timeout 5 --read-timeout 15 "${cmd[@]}" 2>&1)
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
    
    # Add no-retry flag for performance optimization
    # Disables exponential backoff retry logic since we handle errors gracefully
    oci_args+=("--no-retry")
    
    # Add timeout flags for faster failure on network issues
    # Connection timeout: 5s (down from 10s default)
    # Read timeout: 15s (down from 60s default) 
    oci_args+=("--connection-timeout" "5")
    oci_args+=("--read-timeout" "15")
    
    log_debug "Executing OCI debug command: oci ${oci_args[*]} ${cmd[*]}"
    
    set +e
    output=$(oci "${oci_args[@]}" "${cmd[@]}" 2>&1)
    status=$?
    set -e
    
    if [[ $status -ne 0 ]]; then
        log_error "OCI debug command failed with status $status"
        log_error "Command: ${cmd[*]}"
        log_error "Output: $output"
    fi
    
    echo "$output"
    return $status
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
    
    # Check for capacity-related errors
    if echo "$error_output" | grep -qi "capacity\|host capacity\|out of capacity\|service limit\|quota exceeded\|resource unavailable\|insufficient capacity"; then
        log_debug "Detected CAPACITY error pattern in: $error_output"
        echo "CAPACITY"
    # Check for rate limiting (treat as capacity issue)
    elif echo "$error_output" | grep -qi "too.*many.*requests\|rate.*limit\|throttle\|429\|TooManyRequests\|\"code\".*\"TooManyRequests\"\|\"status\".*429\|'status':.*429\|'code':.*'TooManyRequests'"; then
        log_debug "Detected RATE_LIMIT error pattern in: $error_output"
        echo "RATE_LIMIT"
    # Check for limit exceeded errors (special handling needed)
    elif echo "$error_output" | grep -qi "limitexceeded\|limit.*exceeded\|\"code\".*\"LimitExceeded\""; then
        log_debug "Detected LIMIT_EXCEEDED error pattern in: $error_output"
        echo "LIMIT_EXCEEDED"
    # Check for internal/gateway errors (retry-able)
    elif echo "$error_output" | grep -qi "internal.*error\|internalerror\|\"code\".*\"InternalError\"\|bad.*gateway\|502\|\"status\".*502"; then
        log_debug "Detected INTERNAL/GATEWAY error pattern in: $error_output"
        echo "INTERNAL_ERROR"
    # Check for duplicate instances
    elif echo "$error_output" | grep -qi "display name already exists\|instance.*already exists\|duplicate.*name"; then
        log_debug "Detected DUPLICATE error pattern in: $error_output"
        echo "DUPLICATE"
    # Check for authentication/authorization errors
    elif echo "$error_output" | grep -qi "authentication\|authorization\|unauthorized\|forbidden\|401\|403"; then
        log_debug "Detected AUTH error pattern in: $error_output"
        echo "AUTH"
    # Check for network/connectivity errors
    elif echo "$error_output" | grep -qi "network\|timeout\|connection\|unreachable\|dns"; then
        log_debug "Detected NETWORK error pattern in: $error_output"
        echo "NETWORK"
    # Check for configuration errors
    elif echo "$error_output" | grep -qi "not found\|invalid.*id\|does not exist\|bad.*request\|400\|parameter"; then
        log_debug "Detected CONFIG error pattern in: $error_output"
        echo "CONFIG"
    else
        log_debug "No specific error pattern matched in: $error_output"
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

# Validate configuration values don't contain spaces
validate_no_spaces() {
    local var_name="$1"
    local var_value="$2"
    
    if [[ "$var_value" =~ [[:space:]] ]]; then
        log_error "Configuration variable $var_name contains spaces: '$var_value'"
        log_error "Spaces in configuration values can cause command parsing issues"
        return 1
    fi
    return 0
}

# Validate boot volume size constraints
validate_boot_volume_size() {
    local size="$1"
    
    # Check if it's a number
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        log_error "Boot volume size must be a number: $size"
        return 1
    fi
    
    # Check minimum size (Oracle requirement)
    if [[ "$size" -lt 50 ]]; then
        log_error "Boot volume size must be at least 50GB: $size"
        return 1
    fi
    
    # Check reasonable maximum (10TB)
    if [[ "$size" -gt 10000 ]]; then
        log_warning "Boot volume size seems very large: ${size}GB"
    fi
    
    return 0
}

# Validate availability domain format
validate_availability_domain() {
    local ad_list="$1"
    
    # Use a simple loop to split by comma
    local temp_list="$ad_list"
    
    # Process each AD separated by comma
    while [[ "$temp_list" == *","* ]]; do
        # Extract first AD
        local ad="${temp_list%%,*}"
        # Remove leading/trailing spaces
        ad=$(echo "$ad" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Validate this AD
        if [[ -n "$ad" ]] && ! [[ "$ad" =~ ^[a-zA-Z0-9-]+:[A-Z0-9-]+-[A-Z]+-[0-9]+-AD-[0-9]+$ ]]; then
            log_error "Invalid availability domain format: $ad"
            log_error "Expected format: tenancy_prefix:REGION-AD-N (e.g., 'fgaj:AP-SINGAPORE-1-AD-1')"
            return 1
        fi
        
        # Remove processed AD from temp_list
        temp_list="${temp_list#*,}"
    done
    
    # Process the last (or only) AD
    if [[ -n "$temp_list" ]]; then
        local ad=$(echo "$temp_list" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if ! [[ "$ad" =~ ^[a-zA-Z0-9-]+:[A-Z0-9-]+-[A-Z]+-[0-9]+-AD-[0-9]+$ ]]; then
            log_error "Invalid availability domain format: $ad"
            log_error "Expected format: tenancy_prefix:REGION-AD-N (e.g., 'fgaj:AP-SINGAPORE-1-AD-1')"
            return 1
        fi
    fi
    
    return 0
}

# Validate all configuration values for common issues
validate_configuration() {
    local validation_failed=false
    
    log_info "Validating configuration values..."
    
    # Validate required variables don't have spaces
    # NOTE: OPERATING_SYSTEM excluded because "Oracle Linux" is valid and properly quoted
    local vars_to_check=(
        "OCI_TENANCY_OCID:${OCI_TENANCY_OCID:-}"
        "OCI_USER_OCID:${OCI_USER_OCID:-}"
        "OCI_REGION:${OCI_REGION:-}"
        "OCI_AD:${OCI_AD:-}"
        "OCI_SHAPE:${OCI_SHAPE:-}"
        "INSTANCE_DISPLAY_NAME:${INSTANCE_DISPLAY_NAME:-}"
        "OCI_SUBNET_ID:${OCI_SUBNET_ID:-}"
        "OS_VERSION:${OS_VERSION:-}"
    )
    
    for var_def in "${vars_to_check[@]}"; do
        IFS=':' read -r var_name var_value <<< "$var_def"
        if [[ -n "$var_value" ]]; then
            if ! validate_no_spaces "$var_name" "$var_value"; then
                validation_failed=true
            fi
        fi
    done
    
    # Validate boot volume size if set
    if [[ -n "${BOOT_VOLUME_SIZE:-}" ]]; then
        if ! validate_boot_volume_size "$BOOT_VOLUME_SIZE"; then
            validation_failed=true
        fi
    fi
    
    # Validate availability domain format
    if [[ -n "${OCI_AD:-}" ]]; then
        if ! validate_availability_domain "$OCI_AD"; then
            validation_failed=true
        fi
    fi
    
    # Validate OCIDs if present
    local ocid_vars=(
        "OCI_TENANCY_OCID:${OCI_TENANCY_OCID:-}"
        "OCI_USER_OCID:${OCI_USER_OCID:-}"
        "OCI_COMPARTMENT_ID:${OCI_COMPARTMENT_ID:-}"
        "OCI_SUBNET_ID:${OCI_SUBNET_ID:-}"
        "OCI_IMAGE_ID:${OCI_IMAGE_ID:-}"
    )
    
    for ocid_def in "${ocid_vars[@]}"; do
        IFS=':' read -r var_name var_value <<< "$ocid_def"
        if [[ -n "$var_value" ]]; then
            if ! is_valid_ocid "$var_value"; then
                log_error "Invalid OCID format for $var_name: $var_value"
                validation_failed=true
            fi
        fi
    done
    
    if [[ "$validation_failed" == true ]]; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_success "Configuration validation passed"
    return 0
}