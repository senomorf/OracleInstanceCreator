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
    echo "${BLUE}[INFO]${RESET} $*"
}

log_success() {
    echo "${GREEN}[SUCCESS]${RESET} $*"
}

log_warning() {
    echo "${YELLOW}[WARNING]${RESET} $*"
}

log_error() {
    echo "${RED}[ERROR]${RESET} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "${BOLD}[DEBUG]${RESET} $*"
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

# OCI CLI command wrapper with error handling
oci_cmd() {
    local cmd=("$@")
    local output
    local status
    
    log_debug "Executing OCI command: ${cmd[*]}"
    
    set +e
    output=$(oci "${cmd[@]}" 2>&1)
    status=$?
    set -e
    
    if [[ $status -ne 0 ]]; then
        log_error "OCI command failed with status $status"
        log_error "Command: ${cmd[*]}"
        log_error "Output: $output"
        return $status
    fi
    
    echo "$output"
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
    
    if echo "$error_output" | grep -qi "capacity\|host capacity\|out of capacity"; then
        echo "CAPACITY"
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