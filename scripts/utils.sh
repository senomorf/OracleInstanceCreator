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
# Use simple variables instead of associative arrays for macOS compatibility

start_timer() {
    local timer_name="$1"
    local var_name="TIMER_START_${timer_name}"
    eval "${var_name}=$(date +%s.%N)"
    log_debug "Started timer: $timer_name"
}

log_elapsed() {
    local timer_name="$1"
    local var_name="TIMER_START_${timer_name}"
    local start_time="${!var_name:-}"
    
    if [[ -n "$start_time" ]]; then
        local end_time=$(date +%s.%N)
        local elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        log_info "Timer '$timer_name' elapsed: ${elapsed}s"
        unset "$var_name"
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
    
    if echo "$error_output" | grep -qi "capacity\|host capacity\|out of capacity\|service limit\|quota exceeded\|resource unavailable\|insufficient capacity"; then
        log_debug "Detected CAPACITY error pattern in: $error_output"
        echo "CAPACITY"
    elif echo "$error_output" | grep -qi "too.*many.*requests\|rate.*limit\|throttle\|429\|TooManyRequests\|\"code\".*\"TooManyRequests\"\|\"status\".*429\|'status':.*429\|'code':.*'TooManyRequests'"; then
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

# URL encoding/decoding functions for proxy credentials
url_encode() {
    local string="$1"
    local encoded=""
    local i
    
    for ((i = 0; i < ${#string}; i++)); do
        local char="${string:$i:1}"
        case "$char" in
            [a-zA-Z0-9._~-]) encoded+="$char" ;;
            *) printf -v encoded "%s%%%02X" "$encoded" "'$char" ;;
        esac
    done
    
    echo "$encoded"
}

url_decode() {
    local string="$1"
    printf '%b\n' "${string//%/\\x}"
}

# Parse and configure proxy from OCI_PROXY_URL environment variable
# Supports both IPv4 and IPv6 addresses with URL encoding
parse_and_configure_proxy() {
    local validate_only="${1:-false}"
    
    if [[ -z "${OCI_PROXY_URL:-}" ]]; then
        log_debug "No OCI_PROXY_URL provided - proxy will not be used"
        return 0
    fi
    
    # Check if proxy is already configured (avoid redundant setup)
    if [[ "${validate_only}" == "false" ]] && [[ -n "${HTTP_PROXY:-}" ]]; then
        log_debug "Proxy already configured - skipping setup"
        return 0
    fi
    
    log_info "Processing OCI_PROXY_URL configuration..."
    
    local proxy_user proxy_pass proxy_host proxy_port
    
    # Check for IPv6 format first (contains brackets)
    if [[ "$OCI_PROXY_URL" == *"@["*"]:"* ]]; then
        log_debug "Detected IPv6 proxy format"
        # Extract IPv6 components manually
        local user_pass="${OCI_PROXY_URL%@\[*}"
        local rest="${OCI_PROXY_URL#*@\[}"
        proxy_host="${rest%\]:*}"
        proxy_port="${rest##*\]:}"
        proxy_user="${user_pass%:*}"
        proxy_pass="${user_pass##*:}"
        
        # Validate IPv6 format
        if [[ -z "$proxy_user" || -z "$proxy_pass" || -z "$proxy_host" || ! "$proxy_port" =~ ^[0-9]+$ ]]; then
            log_error "Invalid IPv6 proxy format. Expected: USER:PASS@[HOST]:PORT"
            log_error "Example: myuser:mypass@[::1]:3128"
            die "Invalid IPv6 proxy configuration"
        fi
    else
        # Try IPv4 format
        local ipv4_pattern="^([^:]+):([^@]+)@([^:]+):([0-9]+)$"
        if [[ "$OCI_PROXY_URL" =~ $ipv4_pattern ]]; then
            proxy_user="${BASH_REMATCH[1]}"
            proxy_pass="${BASH_REMATCH[2]}"
            proxy_host="${BASH_REMATCH[3]}"
            proxy_port="${BASH_REMATCH[4]}"
            log_debug "Detected IPv4 proxy format"
        else
            log_error "Invalid OCI_PROXY_URL format. Expected formats:"
            log_error "  IPv4: USER:PASS@HOST:PORT"
            log_error "  IPv6: USER:PASS@[HOST]:PORT"
            log_error "Examples:"
            log_error "  myuser:mypass@proxy.example.com:3128"
            log_error "  myuser:mypass@192.168.1.100:3128"
            log_error "  myuser:mypass@[::1]:3128"
            die "Invalid proxy configuration - check OCI_PROXY_URL format"
        fi
    fi
    
    # Decode URL-encoded credentials
    proxy_user=$(url_decode "$proxy_user")
    proxy_pass=$(url_decode "$proxy_pass")
    
    # Validate components
    if [[ -z "$proxy_user" || -z "$proxy_pass" ]]; then
        die "Proxy user and password cannot be empty"
    fi
    
    if [[ -z "$proxy_host" ]]; then
        die "Proxy host cannot be empty"
    fi
    
    # Validate port range
    if [[ $proxy_port -lt 1 || $proxy_port -gt 65535 ]]; then
        die "Proxy port must be between 1 and 65535, got: $proxy_port"
    fi
    
    # If validation only, we're done
    if [[ "${validate_only}" == "true" ]]; then
        log_success "Proxy configuration validation passed: ${proxy_host}:${proxy_port}"
        return 0
    fi
    
    # Construct proxy URL with authentication
    local proxy_url="http://${proxy_user}:${proxy_pass}@${proxy_host}:${proxy_port}/"
    
    # Set both uppercase and lowercase versions for maximum compatibility
    export HTTP_PROXY="${proxy_url}"
    export HTTPS_PROXY="${proxy_url}"
    export http_proxy="${proxy_url}"
    export https_proxy="${proxy_url}"
    
    log_debug "Proxy configured for ${proxy_host}:${proxy_port} with authentication (credentials not logged)"
    log_success "Proxy configuration applied successfully"
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