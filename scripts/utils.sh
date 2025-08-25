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

# Logging functions with colors for clear output and optional JSON format
# Set LOG_FORMAT=json to enable structured logging

log_json() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if [[ -n "$context" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\",\"context\":$context}" >&2
    else
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >&2
    fi
}

log_info() {
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        log_json "info" "$*"
    else
        echo "${BLUE}[INFO]${RESET} $*" >&2
    fi
}

log_success() {
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        log_json "success" "$*"
    else
        echo "${GREEN}[SUCCESS]${RESET} $*" >&2
    fi
}

log_warning() {
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        log_json "warning" "$*"
    else
        echo "${YELLOW}[WARNING]${RESET} $*" >&2
    fi
}

log_error() {
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        log_json "error" "$*"
    else
        echo "${RED}[ERROR]${RESET} $*" >&2
    fi
}

log_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        if [[ "${LOG_FORMAT:-}" == "json" ]]; then
            log_json "debug" "$*"
        else
            echo "${BOLD}[DEBUG]${RESET} $*" >&2
        fi
    fi
}

# Enhanced logging with context (useful for structured logging)
# Parameters: level, message, optional JSON context object
log_with_context() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    if [[ "${LOG_FORMAT:-}" == "json" ]]; then
        log_json "$level" "$message" "$context"
    else
        # For text format, just log normally (context ignored)
        case "$level" in
            "info") log_info "$message" ;;
            "success") log_success "$message" ;;
            "warning") log_warning "$message" ;;
            "error") log_error "$message" ;;
            "debug") log_debug "$message" ;;
            *) echo "[$level] $message" >&2 ;;
        esac
    fi
}

# Timing functions for performance monitoring
# Note: Using bash 4+ associative arrays if available, otherwise simple variables
if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
    declare -A TIMER_START_TIMES
else
    # Fallback for older bash versions - use simple timer variable
    TIMER_START_TIME=""
fi

start_timer() {
    local timer_name="$1"
    if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
        TIMER_START_TIMES[$timer_name]=$(date +%s.%N)
    else
        # Fallback - only support one timer at a time
        TIMER_START_TIME=$(date +%s.%N)
    fi
    log_debug "Started timer: $timer_name"
}

log_elapsed() {
    local timer_name="$1"
    local start_time=""
    
    if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
        start_time="${TIMER_START_TIMES[$timer_name]:-}"
        if [[ -n "$start_time" ]]; then
            unset TIMER_START_TIMES[$timer_name]
        fi
    else
        # Fallback - use single timer
        start_time="$TIMER_START_TIME"
        TIMER_START_TIME=""
    fi
    
    if [[ -n "$start_time" ]]; then
        local end_time=$(date +%s.%N)
        local elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        log_info "Timer '$timer_name' elapsed: ${elapsed}s"
    else
        log_warning "Timer '$timer_name' was not started"
    fi
}

# Error handling
die() {
    local message="$1"
    local exit_code="${2:-1}"  # Default to general error
    log_error "$message"
    exit "$exit_code"
}

# Standardized error handling functions using OCI constants
die_config_error() {
    die "$1" "$OCI_EXIT_CONFIG_ERROR"
}

die_capacity_error() {
    die "$1" "$OCI_EXIT_CAPACITY_ERROR"
}

die_timeout_error() {
    die "$1" "$TIMEOUT_EXIT_CODE"
}

# Return standardized exit codes based on error type
handle_error_by_type() {
    local error_message="$1"
    local error_type
    error_type=$(get_error_type "$error_message")
    
    case "$error_type" in
        "CAPACITY"|"RATE_LIMIT"|"LIMIT_EXCEEDED")
            return "$OCI_EXIT_CAPACITY_ERROR"
            ;;
        "AUTH"|"CONFIG"|"DUPLICATE")
            return "$OCI_EXIT_CONFIG_ERROR"
            ;;
        "NETWORK"|"INTERNAL_ERROR")
            return "$OCI_EXIT_GENERAL_ERROR"
            ;;
        *)
            return "$OCI_EXIT_GENERAL_ERROR"
            ;;
    esac
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
    output=$(oci --no-retry --connection-timeout $OCI_CONNECTION_TIMEOUT_SECONDS --read-timeout $OCI_READ_TIMEOUT_SECONDS "${cmd[@]}" 2>&1)
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

# Redact sensitive parameters from command arrays for secure logging
#
# This function processes OCI CLI command arguments and masks sensitive
# information before logging. Essential for debug mode security to prevent
# credential exposure in logs.
#
# Parameters:
#   cmd   Array of command arguments to process
# Returns:
#   Space-separated string with sensitive data redacted
#
# Redaction Rules:
# - OCIDs: Show first and last 4 characters (ocid1234...5678)
# - SSH keys: Replace with [SSH_KEY_REDACTED]
# - Private keys: Replace with [PRIVATE_KEY_REDACTED]
# - Auth parameters: Replace values with [REDACTED]
#
# This prevents credential leakage while maintaining debug visibility.
redact_sensitive_params() {
    local cmd=("$@")
    local redacted_cmd=()
    local i=0
    
    while [[ $i -lt ${#cmd[@]} ]]; do
        local param="${cmd[$i]}"
        
        # Check if this is a parameter that might contain sensitive data
        if [[ "$param" == "--auth" || "$param" == "--private-key" || "$param" == "--key-file" ]]; then
            redacted_cmd+=("$param")
            ((i++))
            if [[ $i -lt ${#cmd[@]} ]]; then
                redacted_cmd+=("[REDACTED]")
                ((i++))
            fi
        elif [[ "$param" =~ ^ocid1\. ]]; then
            # Redact OCIDs by showing only first and last 4 characters
            local ocid_length=${#param}
            if [[ $ocid_length -gt 8 ]]; then
                local redacted_ocid="${param:0:4}...${param: -4}"
                redacted_cmd+=("$redacted_ocid")
            else
                redacted_cmd+=("[REDACTED]")
            fi
            ((i++))
        elif [[ "$param" =~ (BEGIN|END).*PRIVATE.*KEY ]]; then
            # Redact private key content
            redacted_cmd+=("[PRIVATE_KEY_REDACTED]")
            ((i++))
        elif [[ "$param" =~ .*@.*:.* ]]; then
            # Mask proxy URLs or credentials in the format user:pass@host:port
            local masked_param
            masked_param=$(mask_credentials "$param")
            redacted_cmd+=("$masked_param")
            ((i++))
        elif [[ "$param" =~ --metadata.*ssh-authorized-keys || "$param" =~ ssh-rsa || "$param" =~ ssh-ed25519 ]]; then
            # Redact SSH keys
            redacted_cmd+=("[SSH_KEY_REDACTED]")
            ((i++))
        else
            redacted_cmd+=("$param")
            ((i++))
        fi
    done
    
    echo "${redacted_cmd[*]}"
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
    
    # Create redacted command for secure logging
    local redacted_cmd_str
    redacted_cmd_str=$(redact_sensitive_params "${cmd[@]}")
    log_debug "Executing OCI debug command: oci ${oci_args[*]} $redacted_cmd_str"
    
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

# Check if jq is available for JSON parsing
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Extract and validate instance OCID from OCI CLI JSON output
#
# Uses jq for robust JSON parsing when available, falls back to regex.
# Validates the extracted OCID format before returning to prevent downstream errors.
#
# Parameters:
#   $1: output - JSON output from OCI CLI command
# Returns:
#   0: Valid OCID found and printed to stdout
#   1: No valid OCID found (prints empty string)
extract_instance_ocid() {
    local output="$1"
    local instance_id=""
    
    # Try jq first for robust JSON parsing
    if has_jq; then
        log_debug "Using jq for JSON parsing to extract instance OCID"
        instance_id=$(echo "$output" | jq -r '.data.id // empty' 2>/dev/null)
        
        # If jq didn't find the OCID, try alternative JSON paths
        if [[ -z "$instance_id" ]]; then
            instance_id=$(echo "$output" | jq -r '.id // .data."instance-id" // empty' 2>/dev/null)
        fi
    fi
    
    # Fallback to regex if jq is not available or didn't find the OCID
    if [[ -z "$instance_id" ]]; then
        log_debug "Using regex fallback to extract instance OCID"
        instance_id=$(echo "$output" | grep -o 'ocid1\.instance[^"]*' | head -1)
    fi
    
    # Validate the extracted OCID format before returning
    if [[ -n "$instance_id" ]]; then
        if is_valid_ocid "$instance_id"; then
            log_debug "Successfully extracted and validated instance OCID: ${instance_id:0:12}...${instance_id: -8}"
            echo "$instance_id"
        else
            log_warning "Extracted string '$instance_id' does not pass OCID format validation"
            echo ""
            return 1
        fi
    else
        log_debug "No instance OCID found in output"
        echo ""
    fi
}

# Classify OCI CLI error output into actionable categories
#
# ALGORITHM: Hierarchical Error Pattern Recognition and Classification
#
# This function implements a sophisticated error analysis system using pattern
# matching to categorize Oracle Cloud errors into actionable response strategies.
# The classification directly drives multi-AD retry logic and workflow outcomes.
#
# ALGORITHM DESIGN PRINCIPLES:
# 1. Specificity Priority: Most specific patterns checked first to prevent misclassification
# 2. Case-Insensitive Matching: Handles Oracle's inconsistent error formatting  
# 3. Multiple Pattern Support: Each category matches various Oracle error formats
# 4. Early Termination: Returns immediately on first match for performance
# 5. Defensive Default: Unknown errors classified as UNKNOWN rather than assumption
#
# CLASSIFICATION HIERARCHY (in order of evaluation):
# ```
# LIMIT_EXCEEDED     → Special case requiring instance verification
#   ↓
# RATE_LIMIT         → Throttling, treat as capacity constraint
#   ↓  
# CAPACITY           → Expected free tier limitation
#   ↓
# INTERNAL_ERROR     → Temporary Oracle service issues
#   ↓
# DUPLICATE          → Instance exists (success condition)
#   ↓
# AUTH               → Credential/permission failures (terminal)
#   ↓
# CONFIG             → Parameter/resource errors (terminal)
#   ↓
# NETWORK            → Connectivity issues (retriable)
#   ↓
# UNKNOWN            → Unrecognized patterns (terminal, requires investigation)
# ```
#
# PATTERN MATCHING STRATEGY:
# - Uses grep -qi for case-insensitive, efficient string matching
# - Multiple patterns per category (OR logic within categories)
# - JSON-aware patterns: Handles both text and JSON error responses
# - HTTP status codes: Recognizes 429, 502, etc. for network issues
#
# PERFORMANCE CONSIDERATIONS:
# - Early termination on first match reduces evaluation overhead
# - Simple grep-based matching faster than complex regex
# - Debug logging only in debug mode to minimize I/O
# - Single-pass evaluation through hierarchical checks
#
# Parameters:
#   error_output  Raw error text from OCI CLI
# Returns:
#   Error classification string
#
# Classifications:
# - LIMIT_EXCEEDED: Oracle limit errors (special verification needed)
# - RATE_LIMIT: Too many requests, throttling
# - CAPACITY: No host capacity, service limits (expected for free tier)
# - INTERNAL_ERROR: Gateway errors, temporary Oracle issues
# - DUPLICATE: Instance already exists (success condition)
# - AUTH: Authentication/authorization failures
# - CONFIG: Invalid parameters, missing resources
# - NETWORK: Connectivity, timeout issues  
# - UNKNOWN: Unrecognized error patterns
#
# Pattern ordering is critical - more specific patterns checked first.
get_error_type() {
    local error_output="$1"
    
    # Check for limit exceeded errors first (more specific than general service limit)
    if echo "$error_output" | grep -qi "limitexceeded\|\"code\".*\"LimitExceeded\""; then
        log_debug "Detected LIMIT_EXCEEDED error pattern in: $error_output"
        echo "LIMIT_EXCEEDED"
    # Check for rate limiting (treat as capacity issue)
    elif echo "$error_output" | grep -qi "too.*many.*requests\|rate.*limit\|throttle\|429\|TooManyRequests\|\"code\".*\"TooManyRequests\"\|\"status\".*429\|'status':.*429\|'code':.*'TooManyRequests'"; then
        log_debug "Detected RATE_LIMIT error pattern in: $error_output"
        echo "RATE_LIMIT"
    # Check for capacity-related errors (more general patterns)
    elif echo "$error_output" | grep -qi "capacity\|host capacity\|out of capacity\|service limit\|quota exceeded\|resource unavailable\|insufficient capacity"; then
        log_debug "Detected CAPACITY error pattern in: $error_output"
        echo "CAPACITY"
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

# Error handling standards for all scripts
# Return codes convention:
# 0 = Success/Continue
# 1 = General error/failure
# 2 = Capacity/rate limit (expected, retry later)
# 3 = Configuration error (fix required)
# 4 = Network/connectivity error (may resolve)
# 124 = Timeout (GNU timeout standard)

# Only define constants if not already defined (avoid readonly conflicts)
if [[ -z "${OCI_EXIT_SUCCESS:-}" ]]; then
    readonly OCI_EXIT_SUCCESS=0
    readonly OCI_EXIT_GENERAL_ERROR=1
    readonly OCI_EXIT_CAPACITY_ERROR=2
    readonly OCI_EXIT_CONFIG_ERROR=3
    readonly OCI_EXIT_NETWORK_ERROR=4
    readonly OCI_EXIT_TIMEOUT=124
fi

# Constants for better maintainability
# Only define if not already defined (avoid readonly conflicts from multiple sourcing)
if [[ -z "${RESULT_FILE_TIMEOUT_SECONDS:-}" ]]; then
    readonly RESULT_FILE_TIMEOUT_SECONDS=10
    readonly RESULT_FILE_POLL_INTERVAL=0.1
    readonly GITHUB_ACTIONS_TIMEOUT_SECONDS=55  # Stay under 60s to avoid 2-minute billing boundary
    readonly OCI_CONNECTION_TIMEOUT_SECONDS=5
    readonly OCI_READ_TIMEOUT_SECONDS=15
    readonly RETRY_WAIT_TIME_DEFAULT=30
    readonly INSTANCE_VERIFY_MAX_CHECKS_DEFAULT=5
    readonly INSTANCE_VERIFY_DELAY_DEFAULT=30
    readonly BOOT_VOLUME_SIZE_DEFAULT=50
    readonly GRACEFUL_TERMINATION_DELAY=2
    
    readonly TIMEOUT_EXIT_CODE=124
fi

# Wait for result file with polling and timeout
wait_for_result_file() {
    local file_path="$1"
    local timeout="${2:-$RESULT_FILE_TIMEOUT_SECONDS}"
    local elapsed=0
    local poll_interval="$RESULT_FILE_POLL_INTERVAL"
    
    log_debug "Waiting for result file: $file_path (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        if [[ -f "$file_path" && -s "$file_path" ]]; then
            log_debug "Result file found and non-empty after ${elapsed}s"
            return 0
        fi
        sleep "$poll_interval"
        elapsed=$((elapsed + 1))
    done
    
    log_warning "Result file not found within ${timeout}s timeout: $file_path"
    return 1
}

# Mask credentials in proxy URLs for safe logging
mask_credentials() {
    local input="$1"
    
    # Pattern matches: user:pass@host or user:pass@[host]
    # Replace credentials with [MASKED]:[MASKED]
    echo "$input" | sed -E 's|([^/@]+):([^/@]+)@|[MASKED]:[MASKED]@|g'
}

# Get appropriate exit code for error type
get_exit_code_for_error_type() {
    local error_type="$1"
    
    case "$error_type" in
        "CAPACITY"|"RATE_LIMIT"|"LIMIT_EXCEEDED")
            echo $OCI_EXIT_CAPACITY_ERROR
            ;;
        "AUTH"|"CONFIG"|"DUPLICATE")
            echo $OCI_EXIT_CONFIG_ERROR
            ;;
        "NETWORK"|"INTERNAL_ERROR")
            echo $OCI_EXIT_NETWORK_ERROR
            ;;
        "TIMEOUT")
            echo $OCI_EXIT_TIMEOUT
            ;;
        *)
            echo $OCI_EXIT_GENERAL_ERROR
            ;;
    esac
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
            *) 
                # Convert character to hex
                printf -v encoded "%s%%%02X" "$encoded" "'$char"
                ;;
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
    
    local proxy_user proxy_pass proxy_host proxy_port is_ipv6=false
    
    # Check for IPv6 format first (contains brackets)
    if [[ "$OCI_PROXY_URL" == *"@["*"]:"* ]]; then
        log_debug "Detected IPv6 proxy format"
        is_ipv6=true
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
    
    # Re-encode credentials to handle special characters in final URL
    local encoded_user=$(url_encode "$proxy_user")
    local encoded_pass=$(url_encode "$proxy_pass")
    
    # Construct proxy URL with authentication and proper IPv6 bracketing
    local proxy_url
    if [[ "$is_ipv6" == "true" ]]; then
        proxy_url="http://${encoded_user}:${encoded_pass}@[${proxy_host}]:${proxy_port}/"
        log_debug "Constructed IPv6 proxy URL with brackets: [${proxy_host}]:${proxy_port}"
    else
        proxy_url="http://${encoded_user}:${encoded_pass}@${proxy_host}:${proxy_port}/"
        log_debug "Constructed IPv4 proxy URL: ${proxy_host}:${proxy_port}"
    fi
    
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
    
    # Check for empty input
    if [[ -z "$ad_list" ]]; then
        log_error "Availability domain cannot be empty"
        return 1
    fi
    
    # Check for leading/trailing commas or spaces
    if [[ "$ad_list" =~ ^[[:space:]]*,|,[[:space:]]*$ ]]; then
        log_error "Invalid AD format: leading or trailing commas not allowed"
        log_error "Found: '$ad_list'"
        return 1
    fi
    
    # Check for consecutive commas
    if [[ "$ad_list" =~ ,, ]]; then
        log_error "Invalid AD format: consecutive commas not allowed"
        log_error "Found: '$ad_list'"
        return 1
    fi
    
    # Use a simple loop to split by comma
    local temp_list="$ad_list"
    
    # Process each AD separated by comma
    while [[ "$temp_list" == *","* ]]; do
        # Extract first AD
        local ad="${temp_list%%,*}"
        # Remove leading/trailing spaces
        ad=$(echo "$ad" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Validate this AD
        if [[ -z "$ad" ]]; then
            log_error "Empty availability domain found in comma-separated list"
            return 1
        fi
        
        if ! [[ "$ad" =~ ^[a-zA-Z0-9-]+:[A-Z0-9-]+-[A-Z]+-[0-9]+-AD-[0-9]+$ ]]; then
            log_error "Invalid availability domain format: '$ad'"
            log_error "Expected format: tenancy_prefix:REGION-AD-N (e.g., 'fgaj:AP-SINGAPORE-1-AD-1')"
            return 1
        fi
        
        # Remove processed AD from temp_list
        temp_list="${temp_list#*,}"
    done
    
    # Process the last (or only) AD
    if [[ -n "$temp_list" ]]; then
        local ad=$(echo "$temp_list" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ -z "$ad" ]]; then
            log_error "Empty availability domain found at end of list"
            return 1
        fi
        
        if ! [[ "$ad" =~ ^[a-zA-Z0-9-]+:[A-Z0-9-]+-[A-Z]+-[0-9]+-AD-[0-9]+$ ]]; then
            log_error "Invalid availability domain format: '$ad'"
            log_error "Expected format: tenancy_prefix:REGION-AD-N (e.g., 'fgaj:AP-SINGAPORE-1-AD-1')"
            return 1
        fi
    fi
    
    return 0
}

# Validate timeout values are within reasonable bounds
validate_timeout_value() {
    local var_name="$1"
    local value="$2"
    local min_val="$3"
    local max_val="$4"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$var_name must be a positive integer, got: $value"
        return 1
    fi
    
    if [[ "$value" -lt "$min_val" || "$value" -gt "$max_val" ]]; then
        log_error "$var_name must be between $min_val-${max_val} seconds, got: $value"
        return 1
    fi
    
    log_debug "$var_name validation passed: ${value}s (range: $min_val-${max_val}s)"
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
        "BOOT_VOLUME_SIZE:${BOOT_VOLUME_SIZE:-}"
        "RECOVERY_ACTION:${RECOVERY_ACTION:-}"
        "LEGACY_IMDS_ENDPOINTS:${LEGACY_IMDS_ENDPOINTS:-}"
        "RETRY_WAIT_TIME:${RETRY_WAIT_TIME:-}"
        "OCI_IMAGE_ID:${OCI_IMAGE_ID:-}"
        "OCI_KEY_FINGERPRINT:${OCI_KEY_FINGERPRINT:-}"
        "TELEGRAM_TOKEN:${TELEGRAM_TOKEN:-}"
        "TELEGRAM_USER_ID:${TELEGRAM_USER_ID:-}"
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
    
    # Validate boolean values
    local boolean_vars=(
        "LEGACY_IMDS_ENDPOINTS:${LEGACY_IMDS_ENDPOINTS:-}"
        "DEBUG:${DEBUG:-}"
        "ENABLE_NOTIFICATIONS:${ENABLE_NOTIFICATIONS:-}"
        "CHECK_EXISTING_INSTANCE:${CHECK_EXISTING_INSTANCE:-}"
    )
    
    for var_def in "${boolean_vars[@]}"; do
        IFS=':' read -r var_name var_value <<< "$var_def"
        if [[ -n "$var_value" ]]; then
            if [[ "$var_value" != "true" && "$var_value" != "false" ]]; then
                log_error "Boolean configuration variable $var_name must be 'true' or 'false': $var_value"
                validation_failed=true
            fi
        fi
    done
    
    # Validate numeric values
    if [[ -n "${RETRY_WAIT_TIME:-}" ]]; then
        if ! [[ "$RETRY_WAIT_TIME" =~ ^[0-9]+$ ]]; then
            log_error "RETRY_WAIT_TIME must be a positive integer: $RETRY_WAIT_TIME"
            validation_failed=true
        fi
    fi
    
    # Validate recovery action value
    if [[ -n "${RECOVERY_ACTION:-}" ]]; then
        if [[ "$RECOVERY_ACTION" != "RESTORE_INSTANCE" && "$RECOVERY_ACTION" != "STOP_INSTANCE" ]]; then
            log_error "RECOVERY_ACTION must be 'RESTORE_INSTANCE' or 'STOP_INSTANCE': $RECOVERY_ACTION"
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

# Performance metrics logging for multi-AD optimization
log_performance_metric() {
    local metric_type="$1"
    local ad_name="$2"
    local attempt_number="$3"
    local total_attempts="$4"
    local additional_info="${5:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local metric_line="[$timestamp] $metric_type: AD=$ad_name, Attempt=$attempt_number/$total_attempts"
    
    if [[ -n "$additional_info" ]]; then
        metric_line="$metric_line, Info=$additional_info"
    fi
    
    # Log to both debug output and a performance metrics comment for future analysis
    log_debug "PERF_METRIC: $metric_line"
    
    # In a production environment, these could be sent to monitoring systems
    case "$metric_type" in
        "AD_SUCCESS")
            log_info "Performance: Successful instance creation in $ad_name on attempt $attempt_number"
            ;;
        "AD_FAILURE")
            log_debug "Performance: Failed attempt in $ad_name ($attempt_number/$total_attempts) - $additional_info"
            ;;
        "AD_CYCLE_COMPLETE")
            log_info "Performance: Completed full AD cycle ($total_attempts ADs attempted)"
            ;;
    esac
}


