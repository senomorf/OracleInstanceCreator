#!/bin/bash

# Telegram notification script
# Handles sending notifications via Telegram bot with severity levels:
# - critical: 🚨 Authentication/config failures requiring immediate attention
# - error: ❌ Operational failures
# - warning: ⚠️ Capacity issues, rate limits
# - info: ℹ️ Status updates, informational
# - success: ✅ Successful operations

set -euo pipefail

# Try to source utils.sh with fallback functions
UTILS_PATH="$(dirname "$0")/utils.sh"
if [[ -f "$UTILS_PATH" ]]; then
    # shellcheck source=scripts/utils.sh
    source "$UTILS_PATH"
else
    # Fallback functions when utils.sh is not available (e.g., in GitHub Actions notification job)
    log_debug() { echo "[DEBUG] $*" >&2; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warning() { echo "[WARNING] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    
    # Simple retry implementation as fallback
    retry_with_backoff() {
        local max_attempts="$1"
        local delay="$2"
        shift 2
        
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if "$@"; then
                return 0
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                return 1
            fi
            
            echo "[DEBUG] Retry attempt $attempt failed, waiting ${delay}s..." >&2
            sleep "$delay"
            ((attempt++))
            delay=$((delay * 2))  # Exponential backoff
        done
        return 1
    }
fi

# Send Telegram notification
send_telegram_notification() {
    local notification_type="$1"  # success, error, critical, warning, info
    local message="$2"
    
    # Validate required environment variables
    if [[ -z "${TELEGRAM_TOKEN:-}" ]] || [[ -z "${TELEGRAM_USER_ID:-}" ]]; then
        log_warning "Telegram credentials not configured, skipping notification"
        return 0
    fi
    
    # Add emoji and formatting based on notification type
    local formatted_message
    case "$notification_type" in
        "success")
            formatted_message="✅ **SUCCESS**: $message"
            ;;
        "error")
            formatted_message="❌ **ERROR**: $message"
            ;;
        "critical")
            formatted_message="🚨 **CRITICAL**: $message"
            ;;
        "warning")
            formatted_message="⚠️ **WARNING**: $message"
            ;;
        "info")
            formatted_message="ℹ️ **INFO**: $message"
            ;;
        *)
            formatted_message="💬 $message"
            ;;
    esac
    
    # Add timestamp
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
    formatted_message="$formatted_message

*Time*: $timestamp
*Workflow*: Oracle Instance Creator (Parallel)"
    
    log_debug "Sending Telegram notification: $notification_type"
    
    # Send notification using curl
    local response
    local status
    
    set +e
    response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_USER_ID}" \
        -d "parse_mode=Markdown" \
        --data-urlencode "text=${formatted_message}" \
        --connect-timeout 10 \
        --max-time 30 2>&1)
    status=$?
    set -e
    
    if [[ $status -eq 0 ]]; then
        # Check if Telegram API returned success
        if echo "$response" | grep -q '"ok":true'; then
            log_debug "Telegram notification sent successfully"
        else
            log_warning "Telegram API returned error: $response"
        fi
    else
        log_warning "Failed to send Telegram notification (curl exit code: $status)"
        log_debug "Curl error: $response"
    fi
}

# Send notification with retry logic
send_telegram_notification_with_retry() {
    local notification_type="$1"
    local message="$2"
    local max_attempts="${3:-3}"
    
    log_debug "Attempting to send Telegram notification with retry"
    
    if retry_with_backoff "$max_attempts" 5 send_telegram_notification "$notification_type" "$message"; then
        log_debug "Telegram notification sent successfully (with retry)"
    else
        log_error "Failed to send Telegram notification after $max_attempts attempts"
    fi
}

# Send instance creation success notification
notify_instance_created() {
    local instance_name="$1"
    local instance_ocid="$2"
    local region="${OCI_REGION:-unknown}"
    local shape="${OCI_SHAPE:-unknown}"
    
    local message="Oracle Cloud instance created successfully!

**Instance Details:**
• Name: $instance_name
• OCID: $instance_ocid
• Region: $region
• Shape: $shape"
    
    if [[ "$OCI_SHAPE" == *"Flex" ]]; then
        message="$message
• OCPUs: ${OCI_OCPUS:-unknown}
• Memory: ${OCI_MEMORY_IN_GBS:-unknown}GB"
    fi
    
    send_telegram_notification_with_retry "success" "$message"
}

# Send capacity error notification (info level since it's expected)
notify_capacity_unavailable() {
    local shape="${OCI_SHAPE:-unknown}"
    local ad="${OCI_AD:-unknown}"
    
    local message="Oracle Cloud capacity currently unavailable.

**Details:**
• Shape: $shape
• Availability Domain: $ad
• Action: Will retry on next scheduled run"
    
    send_telegram_notification "info" "$message"
}

# Send configuration error notification
notify_configuration_error() {
    local error_message="$1"
    
    local message="Oracle Instance Creator configuration error detected.

**Error:** $error_message

**Action Required:** Check GitHub repository secrets and workflow configuration."
    
    send_telegram_notification_with_retry "error" "$message"
}

# Send authentication error notification
notify_authentication_error() {
    local message="Oracle Cloud authentication failed.

**Possible Causes:**
• Invalid OCI credentials
• Expired API key
• Incorrect user permissions
• Invalid tenancy/compartment configuration

**Action Required:** Verify OCI configuration in GitHub secrets."
    
    send_telegram_notification_with_retry "critical" "$message"
}

# Send network error notification
notify_network_error() {
    local message="Network error occurred during Oracle Cloud operation.

**Possible Causes:**
• Temporary connectivity issues
• OCI service outage
• Firewall/network restrictions

**Action:** Operation will be retried automatically."
    
    send_telegram_notification "warning" "$message"
}

# Send workflow started notification
notify_workflow_started() {
    local message="Oracle Instance Creator workflow started.

**Configuration:**
• Region: ${OCI_REGION:-unknown}
• Shape: ${OCI_SHAPE:-unknown}
• Instance Name: ${INSTANCE_DISPLAY_NAME:-unknown}"
    
    send_telegram_notification "info" "$message"
}

# Send workflow completed notification
notify_workflow_completed() {
    local status="$1"  # success, failed, skipped
    local message="Oracle Instance Creator workflow completed.

**Status:** $status"
    
    case "$status" in
        "success")
            send_telegram_notification "success" "$message"
            ;;
        "failed")
            send_telegram_notification "error" "$message"
            ;;
        "skipped")
            send_telegram_notification "info" "$message"
            ;;
        *)
            send_telegram_notification "info" "$message"
            ;;
    esac
}

# Test Telegram configuration
test_telegram_config() {
    log_info "Testing Telegram configuration..."
    
    local test_message="Oracle Instance Creator - Configuration Test

This is a test message to verify Telegram bot configuration is working correctly.

If you receive this message, the configuration is valid!"
    
    send_telegram_notification "info" "$test_message"
}

# Send instance lifecycle management notifications

# Send notification when instance rotation starts
notify_lifecycle_rotation_started() {
    local shape="$1"
    local instance_count="$2"
    local strategy="$3"
    
    local message="Instance lifecycle rotation initiated.

**Details:**
• Shape: $shape
• Instances to rotate: $instance_count
• Strategy: $strategy
• Reason: Capacity limits reached

This will terminate older instances to free capacity for new deployments."
    
    send_telegram_notification "info" "$message"
}

# Send notification when instance rotation completes
notify_lifecycle_rotation_completed() {
    local shape="$1"
    local terminated_count="$2"
    local success="$3"  # "true" or "false"
    
    local notification_type="success"
    local status="completed successfully"
    
    if [[ "$success" != "true" ]]; then
        notification_type="warning"
        status="completed with issues"
    fi
    
    local message="Instance lifecycle rotation $status.

**Details:**
• Shape: $shape
• Instances terminated: $terminated_count
• Status: $status

Capacity has been freed for new instance creation."
    
    send_telegram_notification "$notification_type" "$message"
}

# Send notification when an instance is terminated for lifecycle management
notify_instance_terminated() {
    local instance_name="$1"
    local instance_id="$2"
    local shape="${3:-unknown}"
    local age_hours="${4:-unknown}"
    local reason="${5:-lifecycle rotation}"
    
    local message="Oracle Cloud instance terminated for lifecycle management.

**Instance Details:**
• Name: $instance_name
• OCID: $instance_id  
• Shape: $shape
• Age: ${age_hours} hours
• Reason: $reason

This was performed automatically to free capacity for new deployments."
    
    send_telegram_notification "warning" "$message"
}

# Send notification for lifecycle management errors
notify_lifecycle_error() {
    local error_message="$1"
    local instance_name="${2:-unknown}"
    
    local message="Instance lifecycle management error occurred.

**Error:** $error_message"
    
    if [[ "$instance_name" != "unknown" ]]; then
        message="$message

**Instance:** $instance_name"
    fi
    
    message="$message

**Action Required:** Check lifecycle management configuration and permissions."
    
    send_telegram_notification_with_retry "error" "$message"
}

# Send notification when lifecycle management prevents instance creation
notify_lifecycle_prevention() {
    local message="Instance lifecycle management prevented unnecessary creation attempts.

**Reason:** All target shapes are at capacity limits and auto-rotation is disabled.

**Recommendation:** 
• Enable AUTO_ROTATE_INSTANCES=true for automatic capacity management
• Or manually manage existing instances to free capacity"
    
    send_telegram_notification "info" "$message"
}

# Send notification for dry-run lifecycle operations
notify_lifecycle_dry_run() {
    local operation="$1"
    local instance_count="$2"
    local shape="${3:-all shapes}"
    
    local message="Instance lifecycle management dry-run completed.

**Operation:** $operation
• Shape: $shape  
• Instances that would be affected: $instance_count

This was a simulation only - no actual changes were made.
Set DRY_RUN=false to perform actual lifecycle operations."
    
    send_telegram_notification "info" "$message"
}

# Function to be called from other scripts (backward compatibility)
# This maintains compatibility with the launch-instance.sh script
send_notification() {
    local type="$1"
    local message="$2"
    send_telegram_notification "$type" "$message"
}

# Run test if called directly with 'test' argument
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ "${1:-}" == "test" ]]; then
        test_telegram_config
    else
        echo "Usage: $0 test"
        echo "  test  - Send test notification to verify configuration"
    fi
fi