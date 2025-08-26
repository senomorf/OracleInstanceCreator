#!/bin/bash

# Adaptive Scheduler Intelligence Script
# Analyzes success patterns and provides scheduling optimization recommendations

set -euo pipefail

source "$(dirname "$0")/utils.sh"

# Adaptive scheduling configuration
PATTERN_ANALYSIS_ENABLED="${SUCCESS_TRACKING_ENABLED:-true}"
export MIN_DATA_POINTS="${MIN_PATTERN_DATA_POINTS:-10}"
PATTERN_WINDOW_DAYS="${PATTERN_WINDOW_DAYS:-30}"

# Get current timing context
get_current_context() {
    local current_hour
    current_hour=$(date -u '+%H')
    local current_dow
    current_dow=$(date -u '+%u')  # 1=Monday, 7=Sunday
    local current_timestamp
    current_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    local schedule_type="unknown"
    local region_local_time=""
    
    # Determine schedule context based on UTC hour
    # This maps UTC time to regional business patterns for optimal scheduling
    # Strip leading zeros to avoid octal interpretation in bash arithmetic
    current_hour=$((10#$current_hour))
    if [[ $current_hour -ge 2 && $current_hour -le 7 ]]; then
        schedule_type="off_peak_aggressive"
        region_local_time="10am-3pm SGT (Low business activity)"
        # 2-7am UTC = 10am-3pm Singapore time (lunch/afternoon lull)
        # This is the most aggressive schedule with 15-minute intervals
    elif [[ ($current_dow -eq 6 || $current_dow -eq 7) && $current_hour -ge 1 && $current_hour -le 6 ]]; then
        schedule_type="weekend_boost" 
        region_local_time="Weekend 9am-2pm SGT (Lower demand)"
        # Weekend boost: 20-minute intervals during weekend mornings
        # Lower overall Oracle Cloud usage on weekends
    else
        schedule_type="conservative_peak"
        region_local_time="Peak business hours SGT"
    fi
    
    echo "$schedule_type|$region_local_time|$current_timestamp"
}

# Record current attempt context for pattern analysis
record_attempt_context() {
    local context_info="$1"
    
    if [[ "$PATTERN_ANALYSIS_ENABLED" != "true" ]]; then
        log_debug "Pattern analysis disabled - skipping context recording"
        return 0
    fi
    
    log_info "Recording attempt context for adaptive scheduling analysis"
    
    # Get existing pattern data
    local existing_data=""
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        existing_data=$(gh variable get SUCCESS_PATTERN_DATA 2>/dev/null || echo "")
    fi
    
    # Prepare new entry
    local new_entry
    new_entry="{\"context\":\"$context_info\",\"timestamp\":\"$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')\",\"type\":\"attempt\"}"
    
    # Update pattern data with size management and validation
    # GitHub repository variables have a 64KB limit, so we maintain a rolling window
    # of the last 50 entries (~10KB), leaving ample buffer for growth
    local updated_data
    if [[ -z "$existing_data" ]]; then
        updated_data="[$new_entry]"
    else
        # Add new entry and keep last 50 entries (prevents size limit issues)
        # Each entry is ~200 bytes, so 50 entries ≈ 10KB << 64KB limit
        updated_data=$(echo "$existing_data" | jq --arg entry "$new_entry" '. + [($entry | fromjson)] | .[-50:]' 2>/dev/null || echo "[$new_entry]")
        
        # Validate data size to ensure we stay well under GitHub's 64KB limit
        local data_size=${#updated_data}
        if [[ $data_size -gt 60000 ]]; then
            log_warning "Pattern data approaching size limit (${data_size}/64KB) - reducing to 40 entries for safety"
            updated_data=$(echo "$updated_data" | jq '.[-40:]' 2>/dev/null || echo "[$new_entry]")
            data_size=${#updated_data}
        fi
        
        log_debug "Pattern data size: ${data_size} bytes ($(echo "$updated_data" | jq 'length' 2>/dev/null || echo "0") entries)"
    fi
    
    # Store updated pattern data with robust error handling
    # Uses retry logic with exponential backoff to handle transient GitHub API failures
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        local max_retries=3
        local retry_count=0
        local success=false
        
        # Retry loop with exponential backoff (2s, 4s, 6s delays)
        # This handles transient network issues and API rate limiting
        while [[ $retry_count -lt $max_retries && "$success" != "true" ]]; do
            if echo "$updated_data" | gh variable set SUCCESS_PATTERN_DATA --body-file - 2>/dev/null; then
                log_debug "Successfully updated pattern tracking data (${#updated_data} bytes)"
                success=true
            else
                retry_count=$((retry_count + 1))
                if [[ $retry_count -lt $max_retries ]]; then
                    log_info "GitHub API failure, retrying... ($retry_count/$max_retries)"
                    sleep $((2 * retry_count))  # Exponential backoff: 2s, 4s, 6s
                else
                    log_error "Failed to update pattern tracking data after $max_retries attempts"
                    log_error "REMEDIATION: Check GitHub token permissions (needs 'variables: write' scope) and network connectivity"
                    log_error "IMPACT: Scheduling optimization will continue with existing data, but pattern learning is disabled"
                    log_warning "Consider verifying: 1) GitHub token is valid, 2) Repository has Actions enabled, 3) No API rate limits exceeded"
                fi
            fi
        done
    else
        log_debug "GitHub CLI or token not available - pattern tracking disabled"
        log_debug "REMEDIATION: Install 'gh' CLI and set GITHUB_TOKEN environment variable to enable adaptive scheduling"
    fi
}

# Analyze success patterns and provide optimization recommendations  
analyze_success_patterns() {
    if [[ "$PATTERN_ANALYSIS_ENABLED" != "true" ]]; then
        log_info "Pattern analysis disabled - using default scheduling strategy"
        return 0
    fi
    
    log_info "Analyzing historical success patterns for scheduling optimization"
    
    # Get pattern data
    local pattern_data=""
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        pattern_data=$(gh variable get SUCCESS_PATTERN_DATA 2>/dev/null || echo "[]")
    fi
    
    if [[ -z "$pattern_data" || "$pattern_data" == "[]" ]]; then
        log_info "No historical pattern data available - using baseline scheduling"
        return 0
    fi
    
    # Basic pattern analysis using jq if available
    if command -v jq >/dev/null 2>&1; then
        local total_attempts
        total_attempts=$(echo "$pattern_data" | jq 'length' 2>/dev/null || echo "0")
        local success_attempts
        success_attempts=$(echo "$pattern_data" | jq '[.[] | select(.type == "success")] | length' 2>/dev/null || echo "0")
        
        if [[ $total_attempts -gt 0 ]]; then
            local success_rate=$((success_attempts * 100 / total_attempts))
            log_info "Pattern Analysis: $success_attempts successes in $total_attempts attempts (${success_rate}% success rate)"
            
            # Analyze success by time window
            analyze_time_patterns "$pattern_data"
        else
            log_info "No pattern data for analysis yet"
        fi
    else
        log_warning "jq not available - skipping detailed pattern analysis"
        log_warning "REMEDIATION: Install 'jq' package to enable detailed scheduling pattern analysis and recommendations"
        log_info "Basic pattern tracking will continue without detailed analytics"
    fi
}

# Analyze success patterns by time window
analyze_time_patterns() {
    local pattern_data="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        return 0
    fi
    
    # Analyze success by hour of day (UTC)
    local hour_analysis=$(echo "$pattern_data" | jq -r '
        [.[] | select(.type == "success")] | 
        group_by(.timestamp[11:13]) | 
        .[] | 
        "\(.[0].timestamp[11:13]):\(length)"
    ' 2>/dev/null || echo "")
    
    if [[ -n "$hour_analysis" ]]; then
        log_info "Success pattern by hour (UTC): $hour_analysis"
    fi
    
    # Provide recommendations based on patterns
    provide_scheduling_recommendations "$pattern_data"
}

# Provide scheduling recommendations based on analysis
provide_scheduling_recommendations() {
    local pattern_data="$1"
    
    log_info "=== ADAPTIVE SCHEDULING RECOMMENDATIONS ==="
    
    # Current schedule effectiveness
    local current_context=$(get_current_context)
    local schedule_type=$(echo "$current_context" | cut -d'|' -f1)
    local region_info=$(echo "$current_context" | cut -d'|' -f2)
    
    log_info "Current schedule: $schedule_type ($region_info)"
    
    # Check if we should adjust strategy based on recent patterns
    if command -v jq >/dev/null 2>&1; then
        local recent_failures=$(echo "$pattern_data" | jq '[.[] | select(.timestamp >= (now - 86400 | strftime("%Y-%m-%dT%H:%M:%S.%3NZ")) and .type == "capacity_failure")] | length' 2>/dev/null || echo "0")
        local recent_successes=$(echo "$pattern_data" | jq '[.[] | select(.timestamp >= (now - 86400 | strftime("%Y-%m-%dT%H:%M:%S.%3NZ")) and .type == "success")] | length' 2>/dev/null || echo "0")
        
        if [[ $recent_failures -gt 5 && $recent_successes -eq 0 ]]; then
            log_info "RECOMMENDATION: High recent failure rate - consider adjusting time windows"
        elif [[ $recent_successes -gt 0 ]]; then
            log_info "RECOMMENDATION: Recent success detected - current strategy effective"
        fi
    fi
    
    # Regional optimization advice
    case "${OCI_REGION:-}" in
        *"ap-singapore"*)
            log_info "REGIONAL TIP: Singapore region - current UTC 2-7am window targets SGT business off-hours"
            ;;
        *"us-"*)
            log_info "REGIONAL TIP: US region - consider adjusting for US business hours (UTC +4-8 offset)"
            ;;
        *"eu-"*)
            log_info "REGIONAL TIP: EU region - consider adjusting for European business hours (UTC +0-2 offset)"
            ;;
        *)
            log_info "REGIONAL TIP: Unknown region - verify optimal time windows for your location"
            ;;
    esac
    
    log_info "================================================"
}

# Check if current time suggests skipping this attempt
should_skip_attempt() {
    if [[ "$PATTERN_ANALYSIS_ENABLED" != "true" ]]; then
        return 1  # Don't skip if analysis disabled
    fi

    # Get pattern data
    local pattern_data=""
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        pattern_data=$(gh variable get SUCCESS_PATTERN_DATA 2>/dev/null || echo "[]")
    fi

    if [[ -z "$pattern_data" || "$pattern_data" == "[]" ]]; then
        return 1 # Not enough data to make a decision
    fi

    # Skip logic: Skip if the last 5 attempts in this hour have failed
    if command -v jq >/dev/null 2>&1; then
        local current_hour_utc
        current_hour_utc=$(date -u '+%H')
        # Strip leading zeros to avoid octal interpretation
        current_hour_utc=$((10#$current_hour_utc))
        local recent_attempts_in_hour
        recent_attempts_in_hour=$(echo "$pattern_data" | jq --arg hour "$current_hour_utc" '[.[] | select(.timestamp[11:13] == $hour)] | .[-5:]')
        local failure_count
        failure_count=$(echo "$recent_attempts_in_hour" | jq '[.[] | select(.type == "capacity_failure")] | length')
        local success_count
        success_count=$(echo "$recent_attempts_in_hour" | jq '[.[] | select(.type == "success")] | length')

        if [[ $(echo "$recent_attempts_in_hour" | jq 'length') -ge 5 && "$failure_count" -ge 5 && "$success_count" -eq 0 ]]; then
            log_info "Adaptive Skip: The last 5 attempts in hour $current_hour_utc UTC have failed. Skipping this attempt."
            return 0 # Skip this attempt
        fi
    fi

    # Get current context for logging
    local current_context=$(get_current_context)
    local schedule_type=$(echo "$current_context" | cut -d'|' -f1)
    log_debug "Schedule context: $schedule_type - proceeding with attempt"
    return 1  # Don't skip
}

# Main adaptive scheduler function
main() {
    log_info "=== ADAPTIVE SCHEDULING INTELLIGENCE ==="
    
    # Get current timing context
    local current_context=$(get_current_context)
    IFS='|' read -r schedule_type region_info timestamp <<< "$current_context"
    
    log_info "Schedule Context: $schedule_type"
    log_info "Regional Context: $region_info"
    
    # Record this attempt for pattern learning
    record_attempt_context "$current_context"
    
    # Analyze historical patterns
    analyze_success_patterns
    
    # Check if we should skip this attempt based on patterns
    if should_skip_attempt; then
        log_info "Adaptive intelligence suggests skipping this attempt window"
        exit 2  # Special exit code for intelligent skip
    fi
    
    log_info "Adaptive analysis complete - proceeding with instance creation attempt"
}

# Run main function if called directly
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi