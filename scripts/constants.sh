#!/bin/bash
# Centralized Configuration Constants for Oracle Instance Creator
# This file contains all magic numbers and configuration constants used throughout the project

# shellcheck disable=SC2034  # Variables defined here are used by other scripts

# Prevent multiple sourcing conflicts
if [[ -n "${OIC_CONSTANTS_LOADED:-}" ]]; then
    return 0
fi
readonly OIC_CONSTANTS_LOADED=true

# =============================================================================
# GITHUB ACTIONS & BILLING OPTIMIZATION
# =============================================================================

# GitHub Actions billing optimization - stay under 60s to avoid 2-minute billing boundary
# CRITICAL BILLING LOGIC: GitHub Actions bills in whole-minute increments
# - Jobs under 60s = 1 minute billing
# - Jobs 60s+ = 2 minutes billing 
# - 55s timeout provides 5s safety buffer for job cleanup/finalization
# - This optimization saves 50% cost vs 2-minute billing (1 min vs 2 min per run)
readonly GITHUB_ACTIONS_BILLING_TIMEOUT=55
readonly GITHUB_ACTIONS_BILLING_BOUNDARY=60

# Process monitoring and cleanup timing
readonly PROCESS_MONITORING_INTERVAL=1  # Monitor processes every 1s for responsive detection without excessive CPU usage
readonly GRACEFUL_TERMINATION_DELAY=2   # 2s grace period allows processes proper cleanup before SIGKILL
readonly RESULT_FILE_WAIT_TIMEOUT=30     # 30s max wait handles slow Oracle API responses during parallel execution
readonly RESULT_FILE_POLL_INTERVAL=0.1   # 100ms polling provides responsive detection without excessive CPU load

# =============================================================================
# OCI PERFORMANCE OPTIMIZATION
# =============================================================================

# OCI CLI performance flags - provides 93% improvement (2 minutes -> 20 seconds)
# PERFORMANCE CRITICAL: These flags eliminate OCI CLI's built-in delays
readonly OCI_CONNECTION_TIMEOUT_SECONDS=5   # 5s vs 10s default - faster connection failure detection
readonly OCI_READ_TIMEOUT_SECONDS=15        # 15s vs 60s default - faster read timeout for non-responsive API
readonly OCI_NO_RETRY_FLAG="--no-retry"     # Eliminates OCI's exponential backoff (we handle retries ourselves)

# =============================================================================
# ERROR HANDLING & RETRY CONFIGURATION  
# =============================================================================

# Retry configuration bounds
readonly RETRY_WAIT_TIME_MIN=1
readonly RETRY_WAIT_TIME_MAX=300
readonly RETRY_WAIT_TIME_DEFAULT=30

# Transient error retry configuration with exponential backoff
# RETRY STRATEGY: For INTERNAL_ERROR and NETWORK errors, retry same AD before moving to next
readonly TRANSIENT_ERROR_MAX_RETRIES_MIN=1
readonly TRANSIENT_ERROR_MAX_RETRIES_MAX=10
readonly TRANSIENT_ERROR_MAX_RETRIES_DEFAULT=3      # 3 retries = 4 total attempts per AD
readonly TRANSIENT_ERROR_RETRY_DELAY_MIN=1
readonly TRANSIENT_ERROR_RETRY_DELAY_MAX=60
readonly TRANSIENT_ERROR_RETRY_DELAY_DEFAULT=15     # Base delay for exponential backoff (5s, 10s, 20s, 40s)

# Exit codes following GNU standards
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_CAPACITY_ERROR=2        # Oracle capacity unavailable
readonly EXIT_CONFIG_ERROR=3          # Configuration/authentication errors
readonly EXIT_NETWORK_ERROR=4         # Network/internal errors
readonly EXIT_USER_LIMIT_ERROR=5      # User reached free tier limits (expected success)
readonly EXIT_RATE_LIMIT_ERROR=6      # Oracle API rate limiting (429 errors)
readonly EXIT_TIMEOUT_ERROR=124       # GNU timeout compatibility

# =============================================================================
# INSTANCE CONFIGURATION
# =============================================================================

# Instance verification
readonly INSTANCE_VERIFY_MAX_CHECKS_MIN=1
readonly INSTANCE_VERIFY_MAX_CHECKS_MAX=20
readonly INSTANCE_VERIFY_MAX_CHECKS_DEFAULT=5
readonly INSTANCE_VERIFY_DELAY_MIN=5
readonly INSTANCE_VERIFY_DELAY_MAX=120
readonly INSTANCE_VERIFY_DELAY_DEFAULT=30

# Boot volume configuration
readonly BOOT_VOLUME_SIZE_MIN=50      # Oracle minimum for free tier
readonly BOOT_VOLUME_SIZE_MAX=200     # Reasonable maximum for free tier
readonly BOOT_VOLUME_SIZE_DEFAULT=50

# =============================================================================
# ORACLE CLOUD SHAPES & RESOURCE LIMITS
# =============================================================================

# Free tier shape configurations
readonly A1_FLEX_SHAPE="VM.Standard.A1.Flex"
readonly A1_FLEX_OCPUS=4
readonly A1_FLEX_MEMORY_GB=24
readonly A1_FLEX_INSTANCE_NAME="a1-flex-sg"

readonly E2_MICRO_SHAPE="VM.Standard.E2.1.Micro"  
readonly E2_MICRO_OCPUS=""  # Fixed shape - no OCPU specification needed
readonly E2_MICRO_MEMORY_GB=""  # Fixed shape - no memory specification needed
readonly E2_MICRO_INSTANCE_NAME="e2-micro-sg"

# =============================================================================
# SECURITY & FILE PERMISSIONS
# =============================================================================

# File permissions (octal notation)
readonly SECURE_DIR_PERMISSIONS=700    # Owner read/write/execute only
readonly SECURE_FILE_PERMISSIONS=600   # Owner read/write only
readonly UMASK_SECURE=077              # Ensure no group/other permissions

# =============================================================================
# NETWORKING & PROXY CONFIGURATION
# =============================================================================

# Proxy port validation
readonly PROXY_PORT_MIN=1
readonly PROXY_PORT_MAX=65535
readonly PROXY_DEFAULT_PORT=3128

# =============================================================================
# VALIDATION PATTERNS
# =============================================================================

# OCID validation pattern
readonly OCID_PATTERN='^ocid1\.[a-z0-9]+(\.[a-z0-9-]*)?(\.[a-z0-9-]*)?\..*'

# Availability Domain pattern (comma-separated)
readonly AD_PATTERN='^[a-zA-Z0-9:._-]+(,[a-zA-Z0-9:._-]+)*$'

# Proxy URL patterns
readonly PROXY_IPV4_PATTERN='^(https?://)?([^:@]+):([^:@]+)@([^:@]+):([0-9]+)/?$'
readonly PROXY_IPV6_PATTERN='^(https?://)?([^:@]+):([^:@]+)@\[([0-9a-fA-F:]+)\]:([0-9]+)/?$'

# =============================================================================
# DEBUGGING & LOGGING
# =============================================================================

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1  
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_SUCCESS=4

# =============================================================================
# STATE MANAGEMENT & CACHING
# =============================================================================

# GitHub Actions cache configuration
readonly CACHE_ENABLED_DEFAULT="true"
readonly CACHE_TTL_HOURS_MIN=1
readonly CACHE_TTL_HOURS_MAX=168  # 7 days (GitHub Actions cache limit)
readonly CACHE_TTL_HOURS_DEFAULT=24
readonly CACHE_VERSION="v1"
readonly STATE_FILE_NAME="instance-state.json"

# Cache key generation
readonly CACHE_KEY_PREFIX="oci-instances"
readonly CACHE_PATH_DEFAULT=".cache/oci-state"

# Dynamic TTL configuration
readonly HIGH_CONTENTION_REGIONS="ap-singapore-1,us-ashburn-1,us-phoenix-1,eu-frankfurt-1"
readonly HIGH_CONTENTION_TTL_MULTIPLIER="0.5"  # Half the normal TTL for high-contention regions

# Cache statistics tracking
readonly CACHE_STATS_FILE="cache-stats.json"

# =============================================================================
# HELPER FUNCTIONS FOR CONSTANTS
# =============================================================================

# Get timeout value with validation
get_timeout_value() {
    local env_var="$1"
    local default_value="$2" 
    local min_value="$3"
    local max_value="$4"
    
    local value="${!env_var:-$default_value}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt "$min_value" ]] || [[ "$value" -gt "$max_value" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Validate and get retry configuration
get_retry_config() {
    local config_type="$1"  # 'max_retries' or 'retry_delay'
    
    case "$config_type" in
        "max_retries")
            get_timeout_value "TRANSIENT_ERROR_MAX_RETRIES" "$TRANSIENT_ERROR_MAX_RETRIES_DEFAULT" \
                                "$TRANSIENT_ERROR_MAX_RETRIES_MIN" "$TRANSIENT_ERROR_MAX_RETRIES_MAX"
            ;;
        "retry_delay")
            get_timeout_value "TRANSIENT_ERROR_RETRY_DELAY" "$TRANSIENT_ERROR_RETRY_DELAY_DEFAULT" \
                                "$TRANSIENT_ERROR_RETRY_DELAY_MIN" "$TRANSIENT_ERROR_RETRY_DELAY_MAX"
            ;;
        *)
            echo "Invalid retry config type: $config_type" >&2
            return 1
            ;;
    esac
}

# Export commonly used constants as environment variables
export_common_constants() {
    export GITHUB_ACTIONS_TIMEOUT_SECONDS="$GITHUB_ACTIONS_BILLING_TIMEOUT"
    export OCI_CONNECTION_TIMEOUT="$OCI_CONNECTION_TIMEOUT_SECONDS"
    export OCI_READ_TIMEOUT="$OCI_READ_TIMEOUT_SECONDS"
    export SECURE_UMASK="$UMASK_SECURE"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate all constants are within expected ranges
validate_constants() {
    local errors=0
    
    # Basic sanity checks
    if [[ "$GITHUB_ACTIONS_BILLING_TIMEOUT" -ge "$GITHUB_ACTIONS_BILLING_BOUNDARY" ]]; then
        echo "ERROR: GITHUB_ACTIONS_BILLING_TIMEOUT ($GITHUB_ACTIONS_BILLING_TIMEOUT) must be less than boundary ($GITHUB_ACTIONS_BILLING_BOUNDARY)" >&2
        ((errors++))
    fi
    
    if [[ "$OCI_CONNECTION_TIMEOUT_SECONDS" -ge "$OCI_READ_TIMEOUT_SECONDS" ]]; then
        echo "ERROR: OCI_CONNECTION_TIMEOUT_SECONDS should be less than OCI_READ_TIMEOUT_SECONDS" >&2
        ((errors++))
    fi
    
    if [[ "$BOOT_VOLUME_SIZE_MIN" -lt 50 ]]; then
        echo "ERROR: BOOT_VOLUME_SIZE_MIN ($BOOT_VOLUME_SIZE_MIN) cannot be less than Oracle's minimum (50GB)" >&2
        ((errors++))
    fi
    
    # Cache configuration validation
    if [[ "$CACHE_TTL_HOURS_MIN" -lt 1 ]]; then
        echo "ERROR: CACHE_TTL_HOURS_MIN ($CACHE_TTL_HOURS_MIN) must be at least 1 hour" >&2
        ((errors++))
    fi
    
    if [[ "$CACHE_TTL_HOURS_MAX" -gt 168 ]]; then
        echo "ERROR: CACHE_TTL_HOURS_MAX ($CACHE_TTL_HOURS_MAX) cannot exceed GitHub Actions cache limit (168 hours)" >&2
        ((errors++))
    fi
    
    if [[ "$CACHE_TTL_HOURS_DEFAULT" -lt "$CACHE_TTL_HOURS_MIN" ]] || [[ "$CACHE_TTL_HOURS_DEFAULT" -gt "$CACHE_TTL_HOURS_MAX" ]]; then
        echo "ERROR: CACHE_TTL_HOURS_DEFAULT ($CACHE_TTL_HOURS_DEFAULT) must be between $CACHE_TTL_HOURS_MIN and $CACHE_TTL_HOURS_MAX" >&2
        ((errors++))
    fi
    
    return $errors
}

# Initialize constants validation on source
if ! validate_constants; then
    echo "FATAL: Constants validation failed - check configuration" >&2
    exit 1
fi