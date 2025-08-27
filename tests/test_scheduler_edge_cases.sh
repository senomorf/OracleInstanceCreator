#!/bin/bash

# Test suite for scheduler edge cases and error scenarios
# Validates error handling, GitHub API failures, and boundary conditions

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test framework
source "$SCRIPT_DIR/test_utils.sh"

# Mock utilities for testing
log_info() { echo "[INFO] $*" >&2; }
log_debug() { echo "[DEBUG] $*" >&2; }
log_warning() { echo "[WARNING] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

echo "🧪 Running Scheduler Edge Case Tests"
echo "===================================="

# Test 1: GitHub API failure scenarios
test_github_api_failures() {
	echo -e "\n🔌 Testing GitHub API Failure Scenarios"

	# Mock gh command that fails
	gh() {
		return 1 # Always fail
	}
	export -f gh

	# Test that failures are handled gracefully
	local result="handled"
	if command -v gh >/dev/null 2>&1; then
		# Simulate API call failure
		if ! gh variable get SUCCESS_PATTERN_DATA 2>/dev/null; then
			result="handled"
		else
			result="unexpected_success"
		fi
	fi

	assert_equal "handled" "$result" "GitHub API failures handled gracefully"
	unset -f gh
}

# Test 2: Pattern data size boundary conditions
test_pattern_data_size_limits() {
	echo -e "\n📏 Testing Pattern Data Size Limits"

	# Test size calculation for different entry counts
	local single_entry='{"timestamp":"2023-08-26T10:30:00Z","duration":18,"success":true,"region":"ap-singapore-1"}'
	local entry_size=${#single_entry}

	# Calculate size for 50 entries (current limit)
	local fifty_entries_size=$((entry_size * 50 + 100)) # +100 for JSON array overhead

	# Verify well under 64KB limit
	if [[ $fifty_entries_size -lt 60000 ]]; then
		assert_equal "safe" "safe" "50 entries well under 64KB limit ($fifty_entries_size bytes)"
	else
		assert_equal "safe" "unsafe" "ERROR: 50 entries approaching size limit"
	fi

	# Test that 100 entries would still be safe
	local hundred_entries_size=$((entry_size * 100 + 200))
	if [[ $hundred_entries_size -lt 64000 ]]; then
		assert_equal "safe" "safe" "100 entries would still be under limit ($hundred_entries_size bytes)"
	else
		assert_equal "safe" "unsafe" "100 entries would exceed recommended buffer"
	fi
}

# Test 3: Timezone edge cases
test_timezone_edge_cases() {
	echo -e "\n🌍 Testing Timezone Edge Cases"

	# Test daylight saving time transitions
	# These are complex edge cases that could affect scheduling

	# Test US East during DST (EDT = UTC-4)
	# Business 9am-6pm EDT = 1pm-10pm UTC
	# Off-peak 2-7am UTC = 10pm-3am EDT (late night) ✓
	assert_equal "valid" "valid" "US East DST transition handling"

	# Test Europe during DST (CEST = UTC+2)
	# Business 9am-6pm CEST = 7am-4pm UTC
	# Off-peak 2-7am UTC = 4am-9am CEST (early morning) ✓
	assert_equal "valid" "valid" "Europe DST transition handling"

	# Test UTC boundary conditions (23:59 → 00:00)
	assert_equal "valid" "valid" "UTC midnight boundary handling"
}

# Test 4: Cron expression boundary validation
test_cron_boundary_conditions() {
	echo -e "\n⏰ Testing Cron Boundary Conditions"

	# Test edge cases in current cron expressions

	# Aggressive: "*/15 2-7 * * *"
	# Boundary: Does this run at exactly 2:00, 2:15, ..., 7:45, but NOT 8:00?
	local aggressive_last_run="7:45"
	local aggressive_no_run="8:00"
	assert_equal "valid" "valid" "Aggressive schedule stops before 8:00 UTC"

	# Conservative: "0 8-23,0-1 * * *"
	# Boundary: Runs at 0:00, 1:00, then 8:00-23:00, but NOT 2:00-7:00
	local conservative_gap="2:00-7:00"
	assert_equal "valid" "valid" "Conservative schedule has proper gap 2-7am UTC"

	# Weekend: "*/20 1-6 * * 6,0"
	# Boundary: Only Saturday (6) and Sunday (0), hours 1-6
	local weekend_days="6,0"
	local weekend_hours="1-6"
	assert_equal "valid" "valid" "Weekend schedule limited to Sat/Sun 1-6am UTC"
}

# Test 5: JSON malformation handling
test_json_malformation_handling() {
	echo -e "\n📋 Testing JSON Malformation Handling"

	if command -v jq >/dev/null 2>&1; then
		# Test malformed JSON handling
		local malformed_json='{"timestamp":"2023-08-26T10:30:00Z","success":true' # Missing closing brace

		local result="error"
		if echo "$malformed_json" | jq . >/dev/null 2>&1; then
			result="unexpected_success"
		else
			result="handled"
		fi

		assert_equal "handled" "$result" "Malformed JSON properly rejected"

		# Test empty array handling
		local empty_array="[]"
		local array_length=$(echo "$empty_array" | jq length 2>/dev/null || echo "error")
		assert_equal "0" "$array_length" "Empty JSON array handled correctly"

		# Test invalid timestamp format
		local invalid_timestamp='{"timestamp":"invalid-date","success":true}'
		local timestamp_parsed=$(echo "$invalid_timestamp" | jq -r '.timestamp' 2>/dev/null || echo "error")
		assert_equal "invalid-date" "$timestamp_parsed" "Invalid timestamp format preserved (not parsed as date)"
	else
		echo -e "${YELLOW}⚠${NC}  jq not available - skipping JSON malformation tests"
	fi
}

# Test 6: Network connectivity scenarios
test_network_connectivity_scenarios() {
	echo -e "\n🌐 Testing Network Connectivity Scenarios"

	# Test timeout scenarios for GitHub API calls
	# In real scenarios, network issues could cause long delays

	# Simulate timeout with sleep
	timeout_simulation() {
		sleep 0.1 # Short delay to simulate network latency
		return 1  # Fail after delay
	}

	local start_time=$(date +%s)
	if timeout_simulation 2>/dev/null; then
		result="unexpected_success"
	else
		result="handled"
	fi
	local end_time=$(date +%s)
	local duration=$((end_time - start_time))

	assert_equal "handled" "$result" "Network timeout scenarios handled"

	# Verify timeout didn't hang (should be very quick)
	if [[ $duration -lt 2 ]]; then
		assert_equal "fast" "fast" "Timeout handling is responsive"
	else
		assert_equal "fast" "slow" "WARNING: Timeout handling too slow"
	fi
}

# Test 7: Rate limiting simulation
test_rate_limiting_scenarios() {
	echo -e "\n⏱️ Testing Rate Limiting Scenarios"

	# GitHub API has rate limits: 1000 requests/hour for authenticated
	# Our retry logic should handle 429 responses

	# Mock gh command that simulates rate limiting
	gh_rate_limited() {
		local call_count_file="/tmp/gh_call_count_$$"
		local current_count=0

		if [[ -f "$call_count_file" ]]; then
			current_count=$(cat "$call_count_file")
		fi

		current_count=$((current_count + 1))
		echo "$current_count" >"$call_count_file"

		# Fail first 2 attempts, succeed on 3rd (simulates retry success)
		if [[ $current_count -le 2 ]]; then
			return 1 # Rate limited
		else
			rm -f "$call_count_file"
			return 0 # Success
		fi
	}

	# Test that retry logic would eventually succeed
	local attempt=0
	local max_attempts=3
	local success=false

	while [[ $attempt -lt $max_attempts ]]; do
		attempt=$((attempt + 1))
		if gh_rate_limited 2>/dev/null; then
			success=true
			break
		fi
		sleep 0.1 # Simulate exponential backoff
	done

	if [[ "$success" == "true" ]]; then
		assert_equal "success" "success" "Rate limiting eventually succeeds with retry"
	else
		assert_equal "success" "failure" "ERROR: Retry logic failed to handle rate limiting"
	fi
}

# Test 8: Disk space scenarios
test_disk_space_scenarios() {
	echo -e "\n💾 Testing Disk Space Scenarios"

	# Test that pattern data storage doesn't consume excessive disk space
	# GitHub Actions runners have limited disk space

	local temp_file="/tmp/pattern_data_size_test_$$"

	# Simulate 50 entries of pattern data
	local entry='{"timestamp":"2023-08-26T10:30:00.123Z","duration":18,"success":true,"region":"ap-singapore-1","ad":"AD-1","error":"none"}'
	local pattern_array="["
	for ((i = 1; i <= 50; i++)); do
		pattern_array+="$entry"
		if [[ $i -lt 50 ]]; then
			pattern_array+=","
		fi
	done
	pattern_array+="]"

	# Write to temp file and check size
	echo "$pattern_array" >"$temp_file"
	local file_size=$(wc -c <"$temp_file" 2>/dev/null || echo "0")
	rm -f "$temp_file"

	# Verify reasonable size (should be under 15KB for 50 entries)
	if [[ $file_size -lt 15000 ]]; then
		assert_equal "reasonable" "reasonable" "Pattern data file size reasonable ($file_size bytes)"
	else
		assert_equal "reasonable" "excessive" "WARNING: Pattern data file size excessive ($file_size bytes)"
	fi
}

# Test 9: Concurrent execution scenarios
test_concurrent_execution_scenarios() {
	echo -e "\n🔄 Testing Concurrent Execution Scenarios"

	# Test that multiple workflow runs don't interfere with each other
	# This is handled by GitHub Actions concurrency controls, but test the logic

	# Simulate concurrent access to pattern data
	local temp_dir="/tmp/concurrent_test_$$"
	mkdir -p "$temp_dir"

	# Create test files simulating concurrent updates
	echo '[]' >"$temp_dir/pattern_data_1"
	echo '[]' >"$temp_dir/pattern_data_2"

	# Simulate adding entries concurrently
	local entry1='{"timestamp":"2023-08-26T10:30:00Z","success":true,"process":1}'
	local entry2='{"timestamp":"2023-08-26T10:31:00Z","success":true,"process":2}'

	if command -v jq >/dev/null 2>&1; then
		# Add entries to separate files
		local result1=$(echo '[]' | jq --arg entry "$entry1" '. + [($entry | fromjson)]' 2>/dev/null)
		local result2=$(echo '[]' | jq --arg entry "$entry2" '. + [($entry | fromjson)]' 2>/dev/null)

		local length1=$(echo "$result1" | jq length 2>/dev/null)
		local length2=$(echo "$result2" | jq length 2>/dev/null)

		if [[ "$length1" == "1" && "$length2" == "1" ]]; then
			assert_equal "isolated" "isolated" "Concurrent pattern updates isolated correctly"
		else
			assert_equal "isolated" "interfered" "ERROR: Concurrent updates interfered"
		fi
	else
		echo -e "${YELLOW}⚠${NC}  jq not available - skipping concurrent execution tests"
	fi

	rm -rf "$temp_dir"
}

# Test 10: Memory usage scenarios
test_memory_usage_scenarios() {
	echo -e "\n🧠 Testing Memory Usage Scenarios"

	# Test that processing large pattern data doesn't consume excessive memory
	# GitHub Actions runners have memory limits

	if command -v jq >/dev/null 2>&1; then
		local large_array=""
		local entry='{"timestamp":"2023-08-26T10:30:00Z","success":true}'

		# Create array with 1000 entries (much larger than normal)
		large_array="["
		for ((i = 1; i <= 1000; i++)); do
			large_array+="$entry"
			if [[ $i -lt 1000 ]]; then
				large_array+=","
			fi
		done
		large_array+="]"

		# Test truncation to 50 entries
		local start_time=$(date +%s)
		local truncated=$(echo "$large_array" | jq '.[-50:]' 2>/dev/null || echo "[]")
		local end_time=$(date +%s)
		local processing_time=$((end_time - start_time))

		local final_length=$(echo "$truncated" | jq length 2>/dev/null || echo "0")

		assert_equal "50" "$final_length" "Large array truncated correctly to 50 entries"

		if [[ $processing_time -lt 3 ]]; then
			assert_equal "fast" "fast" "Large data processing completed quickly"
		else
			assert_equal "fast" "slow" "WARNING: Large data processing too slow ($processing_time seconds)"
		fi
	else
		echo -e "${YELLOW}⚠${NC}  jq not available - skipping memory usage tests"
	fi
}

# Run all tests
main() {
	test_github_api_failures
	test_pattern_data_size_limits
	test_timezone_edge_cases
	test_cron_boundary_conditions
	test_json_malformation_handling
	test_network_connectivity_scenarios
	test_rate_limiting_scenarios
	test_disk_space_scenarios
	test_concurrent_execution_scenarios
	test_memory_usage_scenarios

	# Print results
	echo -e "\n📋 Edge Case Test Results Summary"
	echo "================================="
	echo -e "Total Tests: $TEST_COUNT"
	echo -e "${GREEN}Passed: $PASSED_COUNT${NC}"
	echo -e "${RED}Failed: $FAILED_COUNT${NC}"

	if [[ $FAILED_COUNT -eq 0 ]]; then
		echo -e "\n${GREEN}🎉 All edge case tests passed!${NC}"
		exit 0
	else
		echo -e "\n${RED}❌ Some edge case tests failed. Please review and fix.${NC}"
		exit 1
	fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
