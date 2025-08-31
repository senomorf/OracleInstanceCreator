#!/bin/bash

# Real-time Monitoring System for Oracle Instance Creator
# Provides live performance monitoring, alerting, and health checks

set -euo pipefail

# Source utilities and analytics
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/constants.sh"
source "$(dirname "$0")/analytics.sh"
source "$(dirname "$0")/notify.sh"

# Monitoring configuration
readonly MONITORING_INTERVAL="${MONITORING_INTERVAL_SECONDS:-10}"
readonly ALERT_THRESHOLD_CPU="${CPU_ALERT_THRESHOLD:-80}"
readonly ALERT_THRESHOLD_MEMORY="${MEMORY_ALERT_THRESHOLD:-85}"
readonly ALERT_THRESHOLD_EXECUTION="${EXECUTION_TIME_ALERT_THRESHOLD:-30}"
readonly HEALTH_CHECK_ENABLED="${HEALTH_CHECK_ENABLED:-true}"
readonly REAL_TIME_ALERTS="${REAL_TIME_ALERTS_ENABLED:-true}"

# Health check thresholds
readonly OCI_API_TIMEOUT_THRESHOLD=10  # seconds
readonly GITHUB_API_TIMEOUT_THRESHOLD=15  # seconds
readonly DISK_SPACE_THRESHOLD=90  # percentage

# Initialize monitoring system
init_monitoring() {
    log_info "Initializing real-time monitoring system..."
    
    # Create monitoring cache directory
    local monitor_dir="${HOME}/.cache/oci-monitoring"
    if [[ ! -d "$monitor_dir" ]]; then
        mkdir -p "$monitor_dir"
        chmod 700 "$monitor_dir"
    fi
    
    # Initialize health status file
    local health_file="$monitor_dir/health_status.json"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg ts "$timestamp" \
            '{
                last_updated: $ts,
                system_health: "initializing",
                components: {
                    oci_cli: "unknown",
                    github_api: "unknown",
                    disk_space: "unknown",
                    memory: "unknown"
                },
                alerts: []
            }' > "$health_file"
    else
        cat > "$health_file" << EOF
{
    "last_updated": "$timestamp",
    "system_health": "initializing",
    "components": {
        "oci_cli": "unknown",
        "github_api": "unknown", 
        "disk_space": "unknown",
        "memory": "unknown"
    },
    "alerts": []
}
EOF
    fi
    
    log_success "Monitoring system initialized"
    echo "$health_file"
}

# Get current system resource usage
get_system_metrics() {
    local metrics="{}"
    
    # Memory usage
    local memory_usage=0
    if command -v free >/dev/null 2>&1; then
        memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2 }')
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS memory calculation
        memory_usage=$(vm_stat | awk '
        /Pages free/ { free = $3 + 0 }
        /Pages active/ { active = $3 + 0 }
        /Pages inactive/ { inactive = $3 + 0 }
        /Pages wired down/ { wired = $4 + 0 }
        END { 
            total = free + active + inactive + wired
            used = active + inactive + wired
            if (total > 0) printf "%.1f", (used / total) * 100
            else print "0"
        }')
    fi
    
    # CPU usage (if available)
    local cpu_usage=0
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' 2>/dev/null || echo "0")
    fi
    
    # Disk usage
    local disk_usage=0
    if command -v df >/dev/null 2>&1; then
        disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    fi
    
    # Load average
    local load_avg="0.00"
    if [[ -f /proc/loadavg ]]; then
        load_avg=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "0.00")
    elif command -v uptime >/dev/null 2>&1; then
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "0.00")
    fi
    
    # Process count
    local process_count=0
    if command -v ps >/dev/null 2>&1; then
        process_count=$(ps aux | wc -l 2>/dev/null || echo "0")
    fi
    
    # Construct metrics JSON
    if command -v jq >/dev/null 2>&1; then
        metrics=$(jq -n \
            --arg mem "$memory_usage" \
            --arg cpu "$cpu_usage" \
            --arg disk "$disk_usage" \
            --arg load "$load_avg" \
            --arg proc "$process_count" \
            '{
                memory_usage_percent: ($mem | tonumber),
                cpu_usage_percent: ($cpu | tonumber),
                disk_usage_percent: ($disk | tonumber),
                load_average: ($load | tonumber),
                process_count: ($proc | tonumber),
                timestamp: now | strftime("%Y-%m-%dT%H:%M:%S.000Z")
            }')
    else
        local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
        metrics="{\"memory_usage_percent\":$memory_usage,\"cpu_usage_percent\":$cpu_usage,\"disk_usage_percent\":$disk_usage,\"load_average\":$load_avg,\"process_count\":$process_count,\"timestamp\":\"$timestamp\"}"
    fi
    
    echo "$metrics"
}

# Check OCI CLI health and connectivity
check_oci_health() {
    local health_status="healthy"
    local error_message=""
    local response_time=0
    
    # Check if OCI CLI is available
    if ! command -v oci >/dev/null 2>&1; then
        health_status="critical"
        error_message="OCI CLI not found"
        echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"response_time\":$response_time}"
        return
    fi
    
    # Test OCI API connectivity with timeout
    local start_time=$(date +%s.%N)
    local test_result
    
    set +e
    test_result=$(timeout "$OCI_API_TIMEOUT_THRESHOLD" oci iam region list --query 'data[0].name' --raw-output 2>/dev/null)
    local exit_code=$?
    set -e
    
    local end_time=$(date +%s.%N)
    response_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null | awk '{printf "%.3f", $1}')
    
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            health_status="degraded"
            error_message="OCI API timeout (>${OCI_API_TIMEOUT_THRESHOLD}s)"
        else
            health_status="critical"
            error_message="OCI API connectivity failed"
        fi
    elif [[ -z "$test_result" ]]; then
        health_status="degraded"
        error_message="OCI API returned empty response"
    elif [[ $(echo "$response_time > 5" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        health_status="degraded"
        error_message="OCI API slow response (${response_time}s)"
    fi
    
    echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"response_time\":$response_time}"
}

# Check GitHub API health and connectivity
check_github_health() {
    local health_status="healthy"
    local error_message=""
    local response_time=0
    
    # Skip if no GitHub token available
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        health_status="skipped"
        error_message="GitHub token not available"
        echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"response_time\":$response_time}"
        return
    fi
    
    # Check if gh CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        health_status="warning"
        error_message="GitHub CLI not found"
        echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"response_time\":$response_time}"
        return
    fi
    
    # Test GitHub API connectivity with timeout
    local start_time=$(date +%s.%N)
    local test_result
    
    set +e
    test_result=$(timeout "$GITHUB_API_TIMEOUT_THRESHOLD" gh api user --jq '.login' 2>/dev/null)
    local exit_code=$?
    set -e
    
    local end_time=$(date +%s.%N)
    response_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null | awk '{printf "%.3f", $1}')
    
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            health_status="degraded"
            error_message="GitHub API timeout (>${GITHUB_API_TIMEOUT_THRESHOLD}s)"
        else
            health_status="critical"
            error_message="GitHub API connectivity failed"
        fi
    elif [[ -z "$test_result" ]]; then
        health_status="degraded"
        error_message="GitHub API returned empty response"
    elif [[ $(echo "$response_time > 3" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        health_status="degraded"
        error_message="GitHub API slow response (${response_time}s)"
    fi
    
    echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"response_time\":$response_time}"
}

# Check disk space availability
check_disk_space() {
    local health_status="healthy"
    local error_message=""
    local usage_percent=0
    
    if command -v df >/dev/null 2>&1; then
        usage_percent=$(df / | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "0")
        
        if [[ "$usage_percent" -ge "$DISK_SPACE_THRESHOLD" ]]; then
            health_status="critical"
            error_message="Disk usage at ${usage_percent}% (threshold: ${DISK_SPACE_THRESHOLD}%)"
        elif [[ "$usage_percent" -ge 80 ]]; then
            health_status="warning"
            error_message="Disk usage at ${usage_percent}% (approaching threshold)"
        fi
    else
        health_status="unknown"
        error_message="Unable to check disk space"
    fi
    
    echo "{\"status\":\"$health_status\",\"error\":\"$error_message\",\"usage_percent\":$usage_percent}"
}

# Perform comprehensive health check
perform_health_check() {
    local health_file="${1:-${HOME}/.cache/oci-monitoring/health_status.json}"
    
    log_debug "Performing health check..."
    
    # Get system metrics
    local system_metrics
    system_metrics=$(get_system_metrics)
    
    # Check individual components
    local oci_health github_health disk_health
    oci_health=$(check_oci_health)
    github_health=$(check_github_health)
    disk_health=$(check_disk_space)
    
    # Determine overall health status
    local overall_status="healthy"
    local active_alerts=()
    
    # Check OCI health
    local oci_status
    if command -v jq >/dev/null 2>&1; then
        oci_status=$(echo "$oci_health" | jq -r '.status')
    else
        oci_status=$(echo "$oci_health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [[ "$oci_status" == "critical" ]]; then
        overall_status="critical"
        active_alerts+=("OCI API connectivity critical")
    elif [[ "$oci_status" == "degraded" ]] && [[ "$overall_status" == "healthy" ]]; then
        overall_status="degraded"
        active_alerts+=("OCI API performance degraded")
    fi
    
    # Check system resources
    if command -v jq >/dev/null 2>&1; then
        local memory_usage cpu_usage disk_usage
        memory_usage=$(echo "$system_metrics" | jq -r '.memory_usage_percent')
        cpu_usage=$(echo "$system_metrics" | jq -r '.cpu_usage_percent')
        disk_usage=$(echo "$system_metrics" | jq -r '.disk_usage_percent')
        
        # Memory alerts
        if [[ $(echo "$memory_usage >= $ALERT_THRESHOLD_MEMORY" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
            if [[ "$overall_status" == "healthy" ]]; then
                overall_status="warning"
            fi
            active_alerts+=("High memory usage: ${memory_usage}%")
        fi
        
        # CPU alerts
        if [[ $(echo "$cpu_usage >= $ALERT_THRESHOLD_CPU" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
            if [[ "$overall_status" == "healthy" ]]; then
                overall_status="warning"
            fi
            active_alerts+=("High CPU usage: ${cpu_usage}%")
        fi
    fi
    
    # Check disk space
    local disk_status
    if command -v jq >/dev/null 2>&1; then
        disk_status=$(echo "$disk_health" | jq -r '.status')
    else
        disk_status=$(echo "$disk_health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [[ "$disk_status" == "critical" ]]; then
        overall_status="critical"
        active_alerts+=("Critical disk space")
    elif [[ "$disk_status" == "warning" ]] && [[ "$overall_status" == "healthy" ]]; then
        overall_status="warning"
        active_alerts+=("Low disk space")
    fi
    
    # Create comprehensive health report
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local health_report
    
    if command -v jq >/dev/null 2>&1; then
        # Convert alerts array to JSON
        local alerts_json="[]"
        if [[ ${#active_alerts[@]} -gt 0 ]]; then
            alerts_json=$(printf '%s\n' "${active_alerts[@]}" | jq -R . | jq -s .)
        fi
        
        health_report=$(jq -n \
            --arg ts "$timestamp" \
            --arg status "$overall_status" \
            --argjson system "$system_metrics" \
            --argjson oci "$oci_health" \
            --argjson github "$github_health" \
            --argjson disk "$disk_health" \
            --argjson alerts "$alerts_json" \
            '{
                last_updated: $ts,
                system_health: $status,
                components: {
                    oci_cli: $oci,
                    github_api: $github,
                    disk_space: $disk,
                    system_metrics: $system
                },
                alerts: $alerts,
                summary: {
                    total_alerts: ($alerts | length),
                    critical_issues: ([$oci.status, $disk.status] | map(select(. == "critical")) | length),
                    warnings: ([$oci.status, $github.status, $disk.status] | map(select(. == "warning" or . == "degraded")) | length)
                }
            }')
    else
        # Fallback JSON construction
        local alerts_str=""
        if [[ ${#active_alerts[@]} -gt 0 ]]; then
            alerts_str=$(printf '"%s",' "${active_alerts[@]}" | sed 's/,$//')
        fi
        
        health_report="{\"last_updated\":\"$timestamp\",\"system_health\":\"$overall_status\",\"components\":{\"oci_cli\":$oci_health,\"github_api\":$github_health,\"disk_space\":$disk_health,\"system_metrics\":$system_metrics},\"alerts\":[$alerts_str]}"
    fi
    
    # Save health report
    echo "$health_report" > "$health_file"
    
    # Log health status
    case "$overall_status" in
        "healthy")
            log_success "System health: All components operational"
            ;;
        "warning")
            log_warning "System health: ${#active_alerts[@]} warning(s) detected"
            for alert in "${active_alerts[@]}"; do
                log_warning "  • $alert"
            done
            ;;
        "degraded")
            log_warning "System health: Performance degraded (${#active_alerts[@]} issue(s))"
            for alert in "${active_alerts[@]}"; do
                log_warning "  • $alert"
            done
            ;;
        "critical")
            log_error "System health: Critical issues detected (${#active_alerts[@]} issue(s))"
            for alert in "${active_alerts[@]}"; do
                log_error "  • $alert"
            done
            ;;
    esac
    
    # Send alerts if enabled and needed
    if [[ "$REAL_TIME_ALERTS" == "true" ]] && [[ "${#active_alerts[@]}" -gt 0 ]]; then
        send_health_alerts "$overall_status" "${active_alerts[@]}"
    fi
    
    echo "$health_file"
}

# Send health alerts via notification system
send_health_alerts() {
    local health_status="$1"
    shift
    local alerts=("$@")
    
    if [[ "${ENABLE_NOTIFICATIONS:-}" != "true" ]]; then
        return 0
    fi
    
    local alert_message="System Health Alert: $health_status"
    local alert_details=""
    
    for alert in "${alerts[@]}"; do
        alert_details="${alert_details}• $alert\n"
    done
    
    # Determine notification type based on severity
    local notification_type="warning"
    case "$health_status" in
        "critical") notification_type="error" ;;
        "degraded"|"warning") notification_type="warning" ;;
    esac
    
    # Send notification
    send_telegram_notification "$notification_type" "$alert_message" "$alert_details"
}

# Monitor execution in real-time
monitor_execution() {
    local execution_pid="$1"
    local execution_name="${2:-OCI Execution}"
    local max_duration="${3:-60}"
    
    log_info "Starting real-time monitoring for: $execution_name (PID: $execution_pid)"
    
    local start_time=$(date +%s)
    local monitor_interval=5  # Check every 5 seconds
    
    while kill -0 "$execution_pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Get current system metrics
        local metrics
        metrics=$(get_system_metrics)
        
        # Log execution progress
        if command -v jq >/dev/null 2>&1; then
            local memory_usage cpu_usage
            memory_usage=$(echo "$metrics" | jq -r '.memory_usage_percent')
            cpu_usage=$(echo "$metrics" | jq -r '.cpu_usage_percent')
            
            log_debug "Execution monitor: ${elapsed}s elapsed, Memory: ${memory_usage}%, CPU: ${cpu_usage}%"
            
            # Alert on high resource usage
            if [[ $(echo "$memory_usage >= $ALERT_THRESHOLD_MEMORY" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                log_warning "High memory usage during execution: ${memory_usage}%"
            fi
        fi
        
        # Alert on execution timeout
        if [[ $elapsed -ge $max_duration ]]; then
            log_warning "Execution duration exceeded threshold: ${elapsed}s > ${max_duration}s"
            
            # Send alert if enabled
            if [[ "$REAL_TIME_ALERTS" == "true" ]]; then
                send_telegram_notification "warning" "Long-running execution detected" "Execution time: ${elapsed}s (threshold: ${max_duration}s)"
            fi
        fi
        
        sleep $monitor_interval
    done
    
    local total_duration=$(($(date +%s) - start_time))
    log_info "Execution monitoring completed: $execution_name ran for ${total_duration}s"
}

# Display real-time dashboard
show_dashboard() {
    local health_file="${1:-${HOME}/.cache/oci-monitoring/health_status.json}"
    
    if [[ ! -f "$health_file" ]]; then
        log_error "Health status file not found. Run health check first."
        return 1
    fi
    
    # Clear screen and show header
    clear
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    Oracle Instance Creator - Live Dashboard                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Show system health overview
    local health_status
    if command -v jq >/dev/null 2>&1; then
        health_status=$(jq -r '.system_health' "$health_file")
        local last_updated
        last_updated=$(jq -r '.last_updated' "$health_file")
        
        echo "System Health: $health_status (Last updated: $last_updated)"
        echo ""
        
        # Show component status
        echo "Component Status:"
        echo "=================="
        
        local oci_status github_status disk_status
        oci_status=$(jq -r '.components.oci_cli.status' "$health_file")
        github_status=$(jq -r '.components.github_api.status' "$health_file")
        disk_status=$(jq -r '.components.disk_space.status' "$health_file")
        
        printf "%-20s %s\n" "OCI CLI:" "$oci_status"
        printf "%-20s %s\n" "GitHub API:" "$github_status"
        printf "%-20s %s\n" "Disk Space:" "$disk_status"
        echo ""
        
        # Show system metrics
        echo "System Metrics:"
        echo "==============="
        local memory_usage cpu_usage disk_usage load_avg
        memory_usage=$(jq -r '.components.system_metrics.memory_usage_percent' "$health_file")
        cpu_usage=$(jq -r '.components.system_metrics.cpu_usage_percent' "$health_file")
        disk_usage=$(jq -r '.components.system_metrics.disk_usage_percent' "$health_file")
        load_avg=$(jq -r '.components.system_metrics.load_average' "$health_file")
        
        printf "%-20s %.1f%%\n" "Memory Usage:" "$memory_usage"
        printf "%-20s %.1f%%\n" "CPU Usage:" "$cpu_usage"
        printf "%-20s %s%%\n" "Disk Usage:" "$disk_usage"
        printf "%-20s %s\n" "Load Average:" "$load_avg"
        echo ""
        
        # Show active alerts
        local alert_count
        alert_count=$(jq -r '.alerts | length' "$health_file")
        if [[ "$alert_count" -gt 0 ]]; then
            echo "Active Alerts ($alert_count):"
            echo "=============="
            jq -r '.alerts[]' "$health_file" | while read -r alert; do
                echo "  • $alert"
            done
            echo ""
        else
            echo "No active alerts ✓"
            echo ""
        fi
    else
        echo "Dashboard requires jq for JSON parsing"
        echo "Health file content:"
        cat "$health_file"
    fi
    
    echo "Press Ctrl+C to exit dashboard"
}

# Run continuous monitoring
continuous_monitoring() {
    local interval="${1:-$MONITORING_INTERVAL}"
    local health_file
    
    log_info "Starting continuous monitoring (interval: ${interval}s)..."
    
    # Initialize monitoring
    health_file=$(init_monitoring)
    
    # Set up signal handler for graceful shutdown
    trap 'log_info "Stopping continuous monitoring..."; exit 0' SIGTERM SIGINT
    
    while true; do
        perform_health_check "$health_file"
        
        if [[ "${SHOW_DASHBOARD:-false}" == "true" ]]; then
            show_dashboard "$health_file"
        fi
        
        sleep "$interval"
    done
}

# Generate monitoring report
generate_monitoring_report() {
    local report_file="${1:-monitoring_report.md}"
    local health_file="${2:-${HOME}/.cache/oci-monitoring/health_status.json}"
    
    log_info "Generating monitoring report..."
    
    if [[ ! -f "$health_file" ]]; then
        log_error "Health status file not found. Run health check first."
        return 1
    fi
    
    # Create monitoring report
    cat > "$report_file" << EOF
# Oracle Instance Creator - Monitoring Report

**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## System Health Overview

EOF
    
    if command -v jq >/dev/null 2>&1 && [[ -f "$health_file" ]]; then
        local health_status
        health_status=$(jq -r '.system_health' "$health_file")
        
        echo "**Overall Status:** $health_status" >> "$report_file"
        echo "" >> "$report_file"
        
        echo "## Component Health" >> "$report_file"
        echo "" >> "$report_file"
        
        # Component details
        local components=("oci_cli" "github_api" "disk_space")
        for component in "${components[@]}"; do
            local status error response_time
            status=$(jq -r ".components.$component.status" "$health_file")
            error=$(jq -r ".components.$component.error // empty" "$health_file")
            response_time=$(jq -r ".components.$component.response_time // empty" "$health_file")
            
            echo "### ${component^}" >> "$report_file"
            echo "- **Status:** $status" >> "$report_file"
            [[ -n "$error" && "$error" != "null" ]] && echo "- **Error:** $error" >> "$report_file"
            [[ -n "$response_time" && "$response_time" != "null" ]] && echo "- **Response Time:** ${response_time}s" >> "$report_file"
            echo "" >> "$report_file"
        done
        
        # System metrics
        echo "## System Metrics" >> "$report_file"
        echo "" >> "$report_file"
        
        local memory_usage cpu_usage disk_usage load_avg
        memory_usage=$(jq -r '.components.system_metrics.memory_usage_percent' "$health_file")
        cpu_usage=$(jq -r '.components.system_metrics.cpu_usage_percent' "$health_file")
        disk_usage=$(jq -r '.components.system_metrics.disk_usage_percent' "$health_file")
        load_avg=$(jq -r '.components.system_metrics.load_average' "$health_file")
        
        echo "- **Memory Usage:** ${memory_usage}%" >> "$report_file"
        echo "- **CPU Usage:** ${cpu_usage}%" >> "$report_file"
        echo "- **Disk Usage:** ${disk_usage}%" >> "$report_file"
        echo "- **Load Average:** $load_avg" >> "$report_file"
        echo "" >> "$report_file"
        
        # Active alerts
        local alert_count
        alert_count=$(jq -r '.alerts | length' "$health_file")
        
        echo "## Active Alerts" >> "$report_file"
        echo "" >> "$report_file"
        
        if [[ "$alert_count" -gt 0 ]]; then
            jq -r '.alerts[]' "$health_file" | while read -r alert; do
                echo "- $alert" >> "$report_file"
            done
        else
            echo "No active alerts" >> "$report_file"
        fi
    else
        echo "Unable to parse health data - raw content:" >> "$report_file"
        echo "\`\`\`json" >> "$report_file"
        cat "$health_file" >> "$report_file"
        echo "\`\`\`" >> "$report_file"
    fi
    
    log_success "Monitoring report generated: $report_file"
    echo "$report_file"
}

# Main monitoring function
main() {
    local command="${1:-health-check}"
    shift || true
    
    case "$command" in
        "init")
            init_monitoring
            ;;
        "health-check"|"health")
            init_monitoring >/dev/null
            perform_health_check "$@"
            ;;
        "dashboard")
            show_dashboard "$@"
            ;;
        "monitor")
            continuous_monitoring "$@"
            ;;
        "exec-monitor")
            if [[ $# -lt 1 ]]; then
                log_error "Usage: monitoring.sh exec-monitor <pid> [name] [max_duration]"
                exit 1
            fi
            monitor_execution "$@"
            ;;
        "report")
            generate_monitoring_report "$@"
            ;;
        "metrics")
            get_system_metrics
            ;;
        *)
            log_error "Unknown command: $command"
            log_info "Usage: monitoring.sh [init|health-check|dashboard|monitor|exec-monitor|report|metrics]"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions for use by other scripts
export -f init_monitoring get_system_metrics check_oci_health check_github_health
export -f check_disk_space perform_health_check send_health_alerts monitor_execution
export -f show_dashboard continuous_monitoring generate_monitoring_report