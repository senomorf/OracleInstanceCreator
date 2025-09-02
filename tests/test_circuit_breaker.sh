#!/bin/bash

# New circuit breaker test suite with improved mock handling

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="/Users/arsenio/IdeaProjects/OracleInstanceCreator"
export PATH="$PROJECT_ROOT/scripts:$PATH"

# Source the modules to test  
source "$PROJECT_ROOT/scripts/utils.sh" >/dev/null 2>&1
source "$PROJECT_ROOT/scripts/circuit-breaker.sh"

# Test configuration
readonly TEST_AD_1="test:AP-SINGAPORE-1-AD-1"
readonly TEST_AD_2="test:AP-SINGAPORE-1-AD-2"
readonly TEST_AD_3="test:AP-SINGAPORE-1-AD-3"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup persistent mock storage for entire test run
MOCK_GITHUB_VARS_DIR="/tmp/mock_circuit_breaker_$$"
mkdir -p "$MOCK_GITHUB_VARS_DIR"

# Robust mock gh function
gh() {
    case "${1:-} ${2:-}" in
        "variable get")
            local var_name="${3:-}"
            local var_file="$MOCK_GITHUB_VARS_DIR/$var_name"
            if [[ -f "$var_file" ]]; then
                cat "$var_file"
            else
                echo "[]"
            fi
            return 0
            ;;
        "variable set")
            local var_name="${3:-}"
            local var_file="$MOCK_GITHUB_VARS_DIR/$var_name"
            if [[ "${4:-}" == "--body-file" && "${5:-}" == "-" ]]; then
                cat > "$var_file"
            else
                echo "${4:-}" > "$var_file"
            fi
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
export -f gh

echo "INFO: Using mock GitHub CLI for circuit breaker tests"

# Test utilities
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -n "Testing $test_name... "
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Reset state before each test
    echo "[]" | gh variable set AD_FAILURE_DATA --body-file - >/dev/null 2>&1
    
    if $test_function; then
        echo "PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "ASSERTION FAILED: $message"
        fi
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

# Test functions

test_initial_state() {
    # Initially, no AD should be skipped
    if should_skip_ad "$TEST_AD_1"; then
        return 1
    fi
    
    # Failure count should be 0
    local count
    count=$(get_ad_failure_count "$TEST_AD_1")
    assert_equals "0" "$count" "Initial failure count should be 0"
}

test_increment_failure() {
    # Increment failure for AD
    increment_ad_failure "$TEST_AD_1"
    
    # Check failure count
    local count
    count=$(get_ad_failure_count "$TEST_AD_1")
    assert_equals "1" "$count" "Failure count should be 1 after increment"
}

test_multiple_failures() {
    # Add multiple failures
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    
    # Check failure count
    local count
    count=$(get_ad_failure_count "$TEST_AD_1")
    assert_equals "3" "$count" "Failure count should be 3 after three increments"
}

test_circuit_breaker_threshold() {
    # Add failures up to threshold (3)
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    
    # Should trigger circuit breaker
    if ! should_skip_ad "$TEST_AD_1"; then
        echo "AD should be skipped after reaching failure threshold"
        return 1
    fi
}

test_circuit_breaker_below_threshold() {
    # Add failures below threshold (2 < 3)
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    
    # Should not trigger circuit breaker
    if should_skip_ad "$TEST_AD_1"; then
        echo "AD should not be skipped below failure threshold"
        return 1
    fi
}

test_success_reset() {
    # Add failures up to threshold
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    
    # Circuit breaker should be active
    if ! should_skip_ad "$TEST_AD_1"; then
        echo "Circuit breaker should be active"
        return 1
    fi
    
    # Mark success to reset
    mark_ad_success "$TEST_AD_1"
    
    # Circuit breaker should be reset
    if should_skip_ad "$TEST_AD_1"; then
        echo "Circuit breaker should be reset after success"
        return 1
    fi
}

test_multiple_ads() {
    # Add failures to different ADs
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1" 
    increment_ad_failure "$TEST_AD_1"  # AD1 should be skipped
    
    increment_ad_failure "$TEST_AD_2"  # AD2 should not be skipped
    
    # Check circuit breaker status
    if ! should_skip_ad "$TEST_AD_1"; then
        echo "AD1 should be skipped"
        return 1
    fi
    
    if should_skip_ad "$TEST_AD_2"; then
        echo "AD2 should not be skipped"
        return 1
    fi
}

test_get_available_ads() {
    local input_ads="$TEST_AD_1,$TEST_AD_2,$TEST_AD_3"
    
    # Initially all ADs should be available
    local available_ads
    available_ads=$(get_available_ads "$input_ads")
    assert_equals "$input_ads" "$available_ads" "All ADs should be available initially"
    
    # Add failures to first AD
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    increment_ad_failure "$TEST_AD_1"
    
    # First AD should be filtered out
    available_ads=$(get_available_ads "$input_ads")
    local expected="$TEST_AD_2,$TEST_AD_3"
    assert_equals "$expected" "$available_ads" "Failed AD should be filtered out"
}

test_all_ads_filtered() {
    local input_ads="$TEST_AD_1,$TEST_AD_2"
    
    # Add failures to all ADs
    for ad in $TEST_AD_1 $TEST_AD_2; do
        increment_ad_failure "$ad"
        increment_ad_failure "$ad"
        increment_ad_failure "$ad"
    done
    
    # No ADs should be available
    local available_ads
    available_ads=$(get_available_ads "$input_ads")
    assert_equals "" "$available_ads" "No ADs should be available when all have failed"
}

# Run all tests
echo "=== Circuit Breaker Test Suite ==="
echo

run_test "initial state" test_initial_state
run_test "increment failure" test_increment_failure
run_test "multiple failures" test_multiple_failures
run_test "circuit breaker threshold" test_circuit_breaker_threshold
run_test "circuit breaker below threshold" test_circuit_breaker_below_threshold
run_test "success reset" test_success_reset
run_test "multiple ADs" test_multiple_ads
run_test "get available ADs" test_get_available_ads
run_test "all ADs filtered" test_all_ads_filtered

# Test summary
echo
echo "=== Test Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

# Cleanup
rm -rf "$MOCK_GITHUB_VARS_DIR"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All circuit breaker tests passed!"
    exit 0
else
    echo "❌ Some circuit breaker tests failed!"
    exit 1
fi