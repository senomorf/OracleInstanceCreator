#!/bin/bash

# AD Success Rate Metrics Tracking
# Tracks availability domain success/failure rates for optimization

set -euo pipefail

source "$(dirname "$0")/utils.sh"

# Metrics file location (temporary, cleared on each run)
METRICS_FILE="${TMPDIR:-/tmp}/oci_ad_metrics_$$"

# Initialize metrics tracking
init_metrics() {
    # Create temporary metrics file
    echo "# OCI AD Metrics - $(date '+%Y-%m-%d %H:%M:%S')" > "$METRICS_FILE"
    log_debug "Initialized AD metrics tracking: $METRICS_FILE"
}

# Record AD attempt result
# Parameters:
#   $1: ad_name - Availability domain name
#   $2: result - success|failure
#   $3: error_type - CAPACITY|AUTH|CONFIG|NETWORK|etc (for failures)
record_ad_result() {
    local ad_name="$1"
    local result="$2"
    local error_type="${3:-}"
    local timestamp
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format: timestamp|ad_name|result|error_type
    local entry="${timestamp}|${ad_name}|${result}|${error_type}"
    echo "$entry" >> "$METRICS_FILE"
    
    log_debug "Recorded AD result: $ad_name -> $result${error_type:+ ($error_type)}"
}

# Get AD success rate summary
show_ad_metrics() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        log_info "No AD metrics available for this run"
        return
    fi
    
    log_info "=== AD Performance Summary ==="
    
    # Count results by AD
    local ad_stats
    ad_stats=$(awk -F'|' '
        /^#/ { next }  # Skip comment lines
        {
            ad = $2
            result = $3
            error_type = $4
            
            total[ad]++
            if (result == "success") {
                success[ad]++
            } else {
                failure[ad]++
                error_count[ad "_" error_type]++
            }
        }
        END {
            for (ad in total) {
                succ = success[ad] + 0
                fail = failure[ad] + 0
                rate = (total[ad] > 0) ? int((succ / total[ad]) * 100) : 0
                printf "%s: %d%% success (%d/%d attempts)\n", ad, rate, succ, total[ad]
                
                # Show failure breakdown
                if (fail > 0) {
                    printf "  Failures: "
                    first = 1
                    for (key in error_count) {
                        if (index(key, ad "_") == 1) {
                            error_type = substr(key, length(ad) + 2)
                            if (error_type != "") {
                                if (!first) printf ", "
                                printf "%s(%d)", error_type, error_count[key]
                                first = 0
                            }
                        }
                    }
                    printf "\n"
                }
            }
        }
    ' "$METRICS_FILE")
    
    if [[ -n "$ad_stats" ]]; then
        echo "$ad_stats" | while read -r line; do
            log_info "$line"
        done
    else
        log_info "No AD attempts recorded"
    fi
}

# Get best performing AD based on historical data
get_optimal_ad() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo ""
        return
    fi
    
    # Return AD with highest success rate
    awk -F'|' '
        /^#/ { next }
        {
            ad = $2
            result = $3
            total[ad]++
            if (result == "success") success[ad]++
        }
        END {
            best_ad = ""
            best_rate = -1
            
            for (ad in total) {
                succ = success[ad] + 0
                rate = (total[ad] > 0) ? (succ / total[ad]) : 0
                
                if (rate > best_rate) {
                    best_rate = rate
                    best_ad = ad
                }
            }
            
            print best_ad
        }
    ' "$METRICS_FILE"
}

# Clean up metrics file
cleanup_metrics() {
    if [[ -f "$METRICS_FILE" ]]; then
        rm -f "$METRICS_FILE"
        log_debug "Cleaned up metrics file"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_metrics EXIT

# Export functions for use by other scripts
export -f init_metrics record_ad_result show_ad_metrics get_optimal_ad cleanup_metrics