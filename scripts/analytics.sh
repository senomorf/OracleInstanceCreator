#!/bin/bash

# Advanced Analytics Engine for Oracle Instance Creator
# Provides comprehensive performance analysis, trend detection, and optimization insights

set -euo pipefail

# Source utilities for logging and constants
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/constants.sh"

# Analytics configuration
readonly ANALYTICS_CACHE_DIR="${HOME}/.cache/oci-analytics"
readonly METRICS_RETENTION_DAYS="${PERFORMANCE_ANALYTICS_RETENTION_DAYS:-30}"
readonly ANALYSIS_WINDOW_DAYS="${PERFORMANCE_BASELINE_DAYS:-7}"
readonly ANALYTICS_VERSION="1.0.0"

# Initialize analytics infrastructure
init_analytics() {
    # Create analytics cache directory with secure permissions
    if [[ ! -d "$ANALYTICS_CACHE_DIR" ]]; then
        mkdir -p "$ANALYTICS_CACHE_DIR"
        chmod 700 "$ANALYTICS_CACHE_DIR"
        log_debug "Created analytics cache directory: $ANALYTICS_CACHE_DIR"
    fi
    
    # Initialize metrics database file
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    if [[ ! -f "$metrics_db" ]]; then
        touch "$metrics_db"
        chmod 600 "$metrics_db"
        log_debug "Initialized metrics database: $metrics_db"
    fi
    
    # Cleanup old metrics beyond retention period
    cleanup_old_metrics
    
    log_info "Analytics engine initialized (retention: ${METRICS_RETENTION_DAYS}d, analysis window: ${ANALYSIS_WINDOW_DAYS}d)"
}

# Record execution metrics in structured format
record_execution_metric() {
    local metric_type="$1"
    local metric_data="$2"
    local additional_context="${3:-{}}"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    
    # Create structured metric entry
    local metric_entry
    if command -v jq >/dev/null 2>&1; then
        # Validate JSON context first
        if echo "$additional_context" | jq . >/dev/null 2>&1; then
            metric_entry=$(jq -nc \
                --arg ts "$timestamp" \
                --arg type "$metric_type" \
                --arg data "$metric_data" \
                --argjson context "$additional_context" \
                '{
                    timestamp: $ts,
                    metric_type: $type,
                    data: $data,
                    context: $context,
                    version: "'$ANALYTICS_VERSION'"
                }')
        else
            # Fallback if context is not valid JSON
            metric_entry=$(jq -nc \
                --arg ts "$timestamp" \
                --arg type "$metric_type" \
                --arg data "$metric_data" \
                --arg context "$additional_context" \
                '{
                    timestamp: $ts,
                    metric_type: $type,
                    data: $data,
                    context: $context,
                    version: "'$ANALYTICS_VERSION'"
                }')
        fi
    else
        # Fallback without jq
        metric_entry="{\"timestamp\":\"$timestamp\",\"metric_type\":\"$metric_type\",\"data\":\"$metric_data\",\"context\":$additional_context,\"version\":\"$ANALYTICS_VERSION\"}"
    fi
    
    # Append to metrics database
    echo "$metric_entry" >> "$metrics_db"
    log_debug "Recorded metric: $metric_type = $metric_data"
}

# Analyze execution time trends
analyze_execution_trends() {
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    local analysis_start=$(date -u -d "$ANALYSIS_WINDOW_DAYS days ago" '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if [[ ! -f "$metrics_db" ]]; then
        log_warning "No metrics database found for trend analysis"
        return 1
    fi
    
    log_info "Analyzing execution trends (last ${ANALYSIS_WINDOW_DAYS} days)..."
    
    # Extract execution time data
    local trend_data
    if command -v jq >/dev/null 2>&1; then
        trend_data=$(jq -r --arg start "$analysis_start" '
            select(.timestamp >= $start and .metric_type == "execution_time") |
            [.timestamp, .data, .context.shape // "unknown"] |
            @csv
        ' "$metrics_db" 2>/dev/null)
    else
        # Fallback grep approach
        trend_data=$(grep -E "execution_time" "$metrics_db" | grep -v "$analysis_start" || echo "")
    fi
    
    if [[ -z "$trend_data" ]]; then
        log_info "No execution time data found in analysis window"
        return 0
    fi
    
    # Calculate trend statistics
    local stats
    if command -v awk >/dev/null 2>&1; then
        stats=$(echo "$trend_data" | awk -F',' '
        BEGIN { 
            count=0; sum=0; min=999999; max=0
            a1_count=0; a1_sum=0
            e2_count=0; e2_sum=0
        }
        {
            time = $2 + 0
            shape = $3
            count++; sum += time
            if (time < min) min = time
            if (time > max) max = time
            
            if (index(shape, "A1") > 0) {
                a1_count++; a1_sum += time
            } else if (index(shape, "E2") > 0) {
                e2_count++; e2_sum += time
            }
        }
        END {
            if (count > 0) {
                avg = sum / count
                a1_avg = a1_count > 0 ? a1_sum / a1_count : 0
                e2_avg = e2_count > 0 ? e2_sum / e2_count : 0
                
                print "TREND_ANALYSIS|" avg "|" min "|" max "|" count "|" a1_avg "|" e2_avg
            }
        }')
        
        if [[ -n "$stats" ]]; then
            IFS='|' read -r _ avg_time min_time max_time total_runs a1_avg e2_avg <<< "$stats"
            
            log_info "Execution Time Trends:"
            log_info "  • Average: ${avg_time}s (${total_runs} runs)"
            log_info "  • Range: ${min_time}s - ${max_time}s"
            [[ $(echo "$a1_avg > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]] && log_info "  • A1.Flex average: ${a1_avg}s"
            [[ $(echo "$e2_avg > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]] && log_info "  • E2.Micro average: ${e2_avg}s"
            
            # Performance assessment
            if [[ $(echo "$avg_time > 30" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                log_warning "Average execution time >30s indicates potential performance issues"
            elif [[ $(echo "$avg_time < 20" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                log_success "Excellent performance: average execution time <20s"
            fi
        fi
    fi
}

# Analyze success rate patterns
analyze_success_patterns() {
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    local analysis_start=$(date -u -d "$ANALYSIS_WINDOW_DAYS days ago" '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if [[ ! -f "$metrics_db" ]]; then
        log_warning "No metrics database found for success pattern analysis"
        return 1
    fi
    
    log_info "Analyzing success patterns (last ${ANALYSIS_WINDOW_DAYS} days)..."
    
    # Extract success/failure data with time context
    local pattern_data
    if command -v jq >/dev/null 2>&1; then
        pattern_data=$(jq -r --arg start "$analysis_start" '
            select(.timestamp >= $start and .metric_type == "execution_result") |
            [.timestamp, .data, .context.ad // "unknown", .context.hour // "unknown"] |
            @csv
        ' "$metrics_db" 2>/dev/null)
    fi
    
    if [[ -z "$pattern_data" ]]; then
        log_info "No execution result data found in analysis window"
        return 0
    fi
    
    # Analyze patterns by hour and availability domain
    local pattern_stats
    if command -v awk >/dev/null 2>&1; then
        pattern_stats=$(echo "$pattern_data" | awk -F',' '
        BEGIN {
            total_success = 0; total_attempts = 0
        }
        {
            result = $2
            ad = $3
            hour = $4
            
            total_attempts++
            ad_attempts[ad]++
            hour_attempts[hour]++
            
            if (result == "success") {
                total_success++
                ad_success[ad]++
                hour_success[hour]++
            }
        }
        END {
            # Overall success rate
            success_rate = total_attempts > 0 ? (total_success / total_attempts) * 100 : 0
            print "OVERALL|" success_rate "|" total_success "|" total_attempts
            
            # Best performing AD
            best_ad = ""; best_rate = -1
            for (ad in ad_attempts) {
                if (ad_attempts[ad] >= 3) {  # Minimum sample size
                    rate = (ad_success[ad] + 0) / ad_attempts[ad] * 100
                    if (rate > best_rate) {
                        best_rate = rate; best_ad = ad
                    }
                }
            }
            if (best_ad != "") print "BEST_AD|" best_ad "|" best_rate
            
            # Best performing hour
            best_hour = ""; best_hour_rate = -1
            for (hour in hour_attempts) {
                if (hour_attempts[hour] >= 2) {  # Minimum sample size
                    rate = (hour_success[hour] + 0) / hour_attempts[hour] * 100
                    if (rate > best_hour_rate) {
                        best_hour_rate = rate; best_hour = hour
                    }
                }
            }
            if (best_hour != "") print "BEST_HOUR|" best_hour "|" best_hour_rate
        }')
        
        # Parse and display results
        echo "$pattern_stats" | while IFS='|' read -r category value1 value2 value3; do
            case "$category" in
                "OVERALL")
                    log_info "Success Rate Analysis:"
                    log_info "  • Overall success rate: ${value1}% (${value2}/${value3} attempts)"
                    ;;
                "BEST_AD")
                    log_info "  • Best performing AD: $value1 (${value2}% success rate)"
                    ;;
                "BEST_HOUR")
                    log_info "  • Best performing hour: ${value1}:00 UTC (${value2}% success rate)"
                    ;;
            esac
        done
    fi
}

# Analyze API performance metrics
analyze_api_performance() {
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    local analysis_start=$(date -u -d "$ANALYSIS_WINDOW_DAYS days ago" '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if [[ ! -f "$metrics_db" ]]; then
        log_warning "No metrics database found for API performance analysis"
        return 1
    fi
    
    log_info "Analyzing API performance (last ${ANALYSIS_WINDOW_DAYS} days)..."
    
    # Extract API response time data
    local api_data
    if command -v jq >/dev/null 2>&1; then
        api_data=$(jq -r --arg start "$analysis_start" '
            select(.timestamp >= $start and .metric_type == "api_response_time") |
            [.data, .context.operation // "unknown", .context.status // "unknown"] |
            @csv
        ' "$metrics_db" 2>/dev/null)
    fi
    
    if [[ -z "$api_data" ]]; then
        log_info "No API performance data found in analysis window"
        return 0
    fi
    
    # Calculate API performance statistics
    local api_stats
    if command -v awk >/dev/null 2>&1; then
        api_stats=$(echo "$api_data" | awk -F',' '
        BEGIN { 
            count=0; sum=0; min=999999; max=0
            slow_calls=0
        }
        {
            time_ms = $1 + 0
            operation = $2
            status = $3
            
            count++; sum += time_ms
            if (time_ms < min) min = time_ms
            if (time_ms > max) max = time_ms
            if (time_ms > 5000) slow_calls++
        }
        END {
            if (count > 0) {
                avg = sum / count
                slow_pct = (slow_calls / count) * 100
                print "API_STATS|" avg "|" min "|" max "|" count "|" slow_pct
            }
        }')
        
        if [[ -n "$api_stats" ]]; then
            IFS='|' read -r _ avg_ms min_ms max_ms total_calls slow_pct <<< "$api_stats"
            
            log_info "API Performance Analysis:"
            log_info "  • Average response time: ${avg_ms}ms (${total_calls} calls)"
            log_info "  • Response time range: ${min_ms}ms - ${max_ms}ms"
            log_info "  • Slow calls (>5s): ${slow_pct}%"
            
            # Performance assessment
            if [[ $(echo "$avg_ms > 3000" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                log_warning "Average API response time >3s indicates potential network or API issues"
            elif [[ $(echo "$avg_ms < 1000" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                log_success "Excellent API performance: average response time <1s"
            fi
        fi
    fi
}

# Generate optimization recommendations
generate_recommendations() {
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    local recommendations_file="$ANALYTICS_CACHE_DIR/recommendations.txt"
    
    log_info "Generating optimization recommendations..."
    
    # Initialize recommendations file
    cat > "$recommendations_file" << EOF
# OCI Instance Creator - Optimization Recommendations
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Analysis Period: Last $ANALYSIS_WINDOW_DAYS days

EOF
    
    local recommendation_count=0
    
    # Check for performance issues
    if [[ -f "$metrics_db" ]]; then
        local avg_execution_time
        if command -v jq >/dev/null 2>&1; then
            avg_execution_time=$(jq -r '
                select(.metric_type == "execution_time") |
                .data | tonumber
            ' "$metrics_db" 2>/dev/null | awk '
            BEGIN { sum=0; count=0 }
            { sum += $1; count++ }
            END { if (count > 0) print sum/count; else print 0 }')
        else
            avg_execution_time="0"
        fi
        
        if [[ $(echo "$avg_execution_time > 25" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
            echo "## Performance Optimization" >> "$recommendations_file"
            echo "- Average execution time is ${avg_execution_time}s (>25s)" >> "$recommendations_file"
            echo "- Consider reviewing timeout configurations" >> "$recommendations_file"
            echo "- Check network connectivity and proxy settings" >> "$recommendations_file"
            echo "" >> "$recommendations_file"
            ((recommendation_count++))
        fi
    fi
    
    # Check GitHub Actions cache utilization
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        local cache_data
        cache_data=$(gh variable list --json name,value 2>/dev/null | jq -r '.[] | select(.name | contains("CACHE")) | "\(.name): \(.value)"' 2>/dev/null || echo "")
        
        if [[ -z "$cache_data" ]]; then
            echo "## Cache Optimization" >> "$recommendations_file"
            echo "- Enable GitHub Actions cache for faster subsequent runs" >> "$recommendations_file"
            echo "- Configure CACHE_ENABLED=true in environment" >> "$recommendations_file"
            echo "" >> "$recommendations_file"
            ((recommendation_count++))
        fi
    fi
    
    # Check for repeated capacity errors
    if [[ -f "$metrics_db" ]]; then
        local capacity_error_rate
        if command -v jq >/dev/null 2>&1; then
            capacity_error_rate=$(jq -r '
                select(.metric_type == "execution_result") |
                select(.context.error_type == "CAPACITY" or .context.error_type == "ORACLE_CAPACITY_UNAVAILABLE") |
                .data
            ' "$metrics_db" 2>/dev/null | wc -l)
        else
            capacity_error_rate=$(grep -c "CAPACITY\|ORACLE_CAPACITY_UNAVAILABLE" "$metrics_db" 2>/dev/null || echo "0")
        fi
        
        if [[ "$capacity_error_rate" -gt 5 ]]; then
            echo "## Scheduling Optimization" >> "$recommendations_file"
            echo "- High frequency of capacity errors detected ($capacity_error_rate occurrences)" >> "$recommendations_file"
            echo "- Consider adjusting execution schedule to off-peak hours" >> "$recommendations_file"
            echo "- Enable adaptive scheduling for automatic optimization" >> "$recommendations_file"
            echo "" >> "$recommendations_file"
            ((recommendation_count++))
        fi
    fi
    
    # Add resource optimization recommendations
    echo "## Resource Optimization" >> "$recommendations_file"
    echo "- Monitor GitHub Actions minutes usage regularly" >> "$recommendations_file"
    echo "- Use smart shape filtering to avoid unnecessary API calls" >> "$recommendations_file"
    echo "- Consider enabling detailed analytics for better insights" >> "$recommendations_file"
    echo "" >> "$recommendations_file"
    ((recommendation_count++))
    
    if [[ "$recommendation_count" -gt 0 ]]; then
        log_info "Generated $recommendation_count optimization recommendations"
        log_info "Recommendations saved to: $recommendations_file"
        
        # Show recommendations if in interactive mode
        if [[ -t 1 ]] && [[ "${SHOW_RECOMMENDATIONS:-true}" == "true" ]]; then
            log_info ""
            cat "$recommendations_file"
        fi
    else
        echo "# No specific optimization recommendations at this time" >> "$recommendations_file"
        echo "# Current performance appears to be within acceptable ranges" >> "$recommendations_file"
        log_info "No critical optimization recommendations - performance appears optimal"
    fi
}

# Cleanup old metrics beyond retention period
cleanup_old_metrics() {
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    local cutoff_date
    cutoff_date=$(date -u -d "$METRICS_RETENTION_DAYS days ago" '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    if [[ -f "$metrics_db" ]]; then
        local temp_file
        temp_file=$(mktemp)
        
        if command -v jq >/dev/null 2>&1; then
            jq --arg cutoff "$cutoff_date" 'select(.timestamp >= $cutoff)' "$metrics_db" > "$temp_file" 2>/dev/null || true
        else
            # Fallback approach - keep all entries for now
            cp "$metrics_db" "$temp_file"
        fi
        
        # Replace original file if cleanup was successful
        if [[ -s "$temp_file" ]]; then
            mv "$temp_file" "$metrics_db"
            log_debug "Cleaned up metrics older than $METRICS_RETENTION_DAYS days"
        else
            rm -f "$temp_file"
        fi
    fi
}

# Generate comprehensive performance report
generate_performance_report() {
    local report_file="${1:-$ANALYTICS_CACHE_DIR/performance_report.md}"
    
    log_info "Generating comprehensive performance report..."
    
    # Create performance report
    cat > "$report_file" << EOF
# Oracle Instance Creator - Performance Analytics Report

**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')  
**Analysis Period:** Last $ANALYSIS_WINDOW_DAYS days  
**Analytics Version:** $ANALYTICS_VERSION

## Executive Summary

EOF
    
    # Add execution trends section
    echo "## Execution Performance Trends" >> "$report_file"
    echo "" >> "$report_file"
    analyze_execution_trends 2>/dev/null | sed 's/^/    /' >> "$report_file" || echo "    No execution trend data available" >> "$report_file"
    echo "" >> "$report_file"
    
    # Add success patterns section  
    echo "## Success Rate Analysis" >> "$report_file"
    echo "" >> "$report_file"
    analyze_success_patterns 2>/dev/null | sed 's/^/    /' >> "$report_file" || echo "    No success pattern data available" >> "$report_file"
    echo "" >> "$report_file"
    
    # Add API performance section
    echo "## API Performance Metrics" >> "$report_file"
    echo "" >> "$report_file"
    analyze_api_performance 2>/dev/null | sed 's/^/    /' >> "$report_file" || echo "    No API performance data available" >> "$report_file"
    echo "" >> "$report_file"
    
    # Add optimization recommendations
    echo "## Optimization Recommendations" >> "$report_file"
    echo "" >> "$report_file"
    generate_recommendations >/dev/null 2>&1
    if [[ -f "$ANALYTICS_CACHE_DIR/recommendations.txt" ]]; then
        tail -n +4 "$ANALYTICS_CACHE_DIR/recommendations.txt" >> "$report_file"
    fi
    
    log_success "Performance report generated: $report_file"
    
    # Return path for use by other scripts
    echo "$report_file"
}

# Export analytics data for external systems
export_analytics_data() {
    local export_format="${1:-json}"
    local export_file="${2:-$ANALYTICS_CACHE_DIR/analytics_export.$export_format}"
    local metrics_db="$ANALYTICS_CACHE_DIR/metrics.jsonl"
    
    if [[ ! -f "$metrics_db" ]]; then
        log_error "No metrics database found for export"
        return 1
    fi
    
    log_info "Exporting analytics data in $export_format format..."
    
    case "$export_format" in
        "json")
            if command -v jq >/dev/null 2>&1; then
                jq -s '.' "$metrics_db" > "$export_file"
            else
                cp "$metrics_db" "$export_file"
            fi
            ;;
        "csv")
            if command -v jq >/dev/null 2>&1; then
                echo "timestamp,metric_type,data,context" > "$export_file"
                jq -r '[.timestamp, .metric_type, .data, (.context | tostring)] | @csv' "$metrics_db" >> "$export_file"
            else
                echo "timestamp,metric_type,data,context" > "$export_file"
                awk -F',' '{print $1 "," $2 "," $3 "," $4}' "$metrics_db" >> "$export_file"
            fi
            ;;
        *)
            log_error "Unsupported export format: $export_format"
            return 1
            ;;
    esac
    
    log_success "Analytics data exported: $export_file"
    echo "$export_file"
}

# Main analytics function - comprehensive analysis
run_analytics() {
    log_info "Running comprehensive analytics analysis..."
    
    init_analytics
    
    # Run all analysis functions
    analyze_execution_trends
    analyze_success_patterns  
    analyze_api_performance
    
    # Generate report and recommendations
    local report_file
    report_file=$(generate_performance_report)
    
    log_success "Analytics analysis completed - report available at: $report_file"
    
    # Show summary if in interactive mode
    if [[ -t 1 ]] && [[ "${SHOW_ANALYTICS_SUMMARY:-true}" == "true" ]]; then
        echo ""
        log_info "=== Analytics Summary ==="
        head -20 "$report_file" | tail -n +6
    fi
}

# Command line interface
main() {
    local command="${1:-run}"
    shift || true
    
    case "$command" in
        "init")
            init_analytics
            ;;
        "record")
            local metric_type="${1:-}"
            local metric_data="${2:-}"
            local context="${3:-{}}"
            if [[ -z "$metric_type" || -z "$metric_data" ]]; then
                log_error "Usage: analytics.sh record <metric_type> <metric_data> [context_json]"
                exit 1
            fi
            record_execution_metric "$metric_type" "$metric_data" "$context"
            ;;
        "trends")
            init_analytics
            analyze_execution_trends
            ;;
        "patterns")
            init_analytics
            analyze_success_patterns
            ;;
        "api")
            init_analytics
            analyze_api_performance
            ;;
        "recommendations")
            init_analytics
            generate_recommendations
            ;;
        "report")
            generate_performance_report "$@"
            ;;
        "export")
            export_analytics_data "$@"
            ;;
        "run")
            run_analytics
            ;;
        *)
            log_error "Unknown command: $command"
            log_info "Usage: analytics.sh [init|record|trends|patterns|api|recommendations|report|export|run]"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions for use by other scripts
export -f init_analytics record_execution_metric analyze_execution_trends
export -f analyze_success_patterns analyze_api_performance generate_recommendations
export -f cleanup_old_metrics generate_performance_report export_analytics_data run_analytics