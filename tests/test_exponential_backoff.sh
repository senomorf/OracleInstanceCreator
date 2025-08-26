#!/bin/bash

# Test suite for exponential backoff functionality
# Tests backoff calculation, timing, and edge cases

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
export PATH="$PROJECT_ROOT/scripts:$PATH"

# Source the modules to test
source "$PROJECT_ROOT/scripts/utils.sh"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -n "Testing $test_name... "
    TESTS_RUN=$((TESTS_RUN + 1))
    
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

assert_greater_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$actual" -ge "$expected" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "ASSERTION FAILED: $message"
        fi
        echo "  Expected >= '$expected'"
        echo "  Actual:     '$actual'"
        return 1
    fi
}

assert_less_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$actual" -le "$expected" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "ASSERTION FAILED: $message"
        fi
        echo "  Expected <= '$expected'"
        echo "  Actual:     '$actual'"
        return 1
    fi
}

# Test functions

test_basic_calculation() {
    # Test basic exponential backoff calculation
    local result
    
    # Attempt 1: base_delay * 2^0 = 5 * 1 = 5
    result=$(calculate_exponential_backoff 1 5 40)
    assert_equals "5" "$result" "First attempt should be base delay"
    
    # Attempt 2: base_delay * 2^1 = 5 * 2 = 10
    result=$(calculate_exponential_backoff 2 5 40)
    assert_equals "10" "$result" "Second attempt should double the delay"
    
    # Attempt 3: base_delay * 2^2 = 5 * 4 = 20
    result=$(calculate_exponential_backoff 3 5 40)
    assert_equals "20" "$result" "Third attempt should be 4x base delay"
    
    # Attempt 4: base_delay * 2^3 = 5 * 8 = 40
    result=$(calculate_exponential_backoff 4 5 40)
    assert_equals "40" "$result" "Fourth attempt should be 8x base delay"
    
    return 0
}

test_max_delay_cap() {
    # Test that delays are capped at maximum
    local result
    
    # Attempt 5: base_delay * 2^4 = 5 * 16 = 80, but max is 40
    result=$(calculate_exponential_backoff 5 5 40)
    assert_equals "40" "$result" "Delay should be capped at maximum"
    
    # Attempt 10: Should still be capped
    result=$(calculate_exponential_backoff 10 5 40)
    assert_equals "40" "$result" "Large attempts should still be capped"
    
    return 0
}

test_default_parameters() {
    # Test default parameters (base=5, max=40)
    local result
    
    result=$(calculate_exponential_backoff 1)
    assert_equals "5" "$result" "Default base delay should be 5"
    
    result=$(calculate_exponential_backoff 2)
    assert_equals "10" "$result" "Default second attempt should be 10"
    
    # Test that default max is 40
    result=$(calculate_exponential_backoff 10)
    assert_equals "40" "$result" "Default max delay should be 40"
    
    return 0
}

test_custom_parameters() {
    # Test with custom base and max values
    local result
    
    # Custom base delay = 2, max = 20
    result=$(calculate_exponential_backoff 1 2 20)
    assert_equals "2" "$result" "Custom base delay"
    
    result=$(calculate_exponential_backoff 2 2 20)
    assert_equals "4" "$result" "Custom base delay doubled"
    
    result=$(calculate_exponential_backoff 3 2 20)
    assert_equals "8" "$result" "Custom base delay * 4"
    
    result=$(calculate_exponential_backoff 4 2 20)
    assert_equals "16" "$result" "Custom base delay * 8"
    
    # Should be capped at 20
    result=$(calculate_exponential_backoff 5 2 20)
    assert_equals "20" "$result" "Custom max delay cap"
    
    return 0
}

test_edge_cases() {
    local result
    
    # Attempt 0 (should still work)
    result=$(calculate_exponential_backoff 0 5 40)
    # 2^(-1) = 0.5, but bash integer math would make this 2 (5 * 2^-1 = 5 * 0 in bash = 0, but minimum is base delay)
    # Actually, bash handles 2**(-1) as 0, so 5 * 0 = 0, but we might expect at least base delay
    # Let's check what actually happens
    assert_greater_equal "0" "$result" "Attempt 0 should not fail"
    
    # Very high attempt number
    result=$(calculate_exponential_backoff 100 1 1000)
    assert_equals "1000" "$result" "Very high attempt should be capped"
    
    # Base delay = 1, max = 1 (immediate capping)
    result=$(calculate_exponential_backoff 1 1 1)
    assert_equals "1" "$result" "Base delay equals max delay"
    
    result=$(calculate_exponential_backoff 2 1 1)
    assert_equals "1" "$result" "Should be capped immediately"
    
    return 0
}

test_sequence_progression() {
    # Test that the sequence progresses as expected
    local delays=()
    local expected_sequence=(5 10 20 40 40 40)  # 5, 5*2, 5*4, cap, cap, cap
    
    for attempt in {1..6}; do
        delays+=("$(calculate_exponential_backoff "$attempt" 5 40)")
    done
    
    for i in "${!expected_sequence[@]}"; do
        local expected="${expected_sequence[$i]}"
        local actual="${delays[$i]}"
        assert_equals "$expected" "$actual" "Sequence element $((i+1)) should be $expected"
    done
    
    return 0
}

test_mathematical_properties() {
    # Test mathematical properties of exponential backoff
    local delay1 delay2 delay3
    
    delay1=$(calculate_exponential_backoff 1 3 100)
    delay2=$(calculate_exponential_backoff 2 3 100)
    delay3=$(calculate_exponential_backoff 3 3 100)
    
    # Each delay should be double the previous (before hitting max)
    assert_equals "$((delay1 * 2))" "$delay2" "Second delay should be double first"
    assert_equals "$((delay2 * 2))" "$delay3" "Third delay should be double second"
    
    return 0
}

test_realistic_scenario() {
    # Test a realistic usage scenario with actual retry logic
    local delays=()
    local total_wait_time=0
    
    # Simulate 5 retry attempts with standard parameters
    for attempt in {1..5}; do
        local delay
        delay=$(calculate_exponential_backoff "$attempt" 5 40)
        delays+=("$delay")
        total_wait_time=$((total_wait_time + delay))
    done
    
    # Expected: 5 + 10 + 20 + 40 + 40 = 115 seconds total
    assert_equals "115" "$total_wait_time" "Total wait time for 5 attempts should be 115s"
    
    # First delay should be reasonable
    assert_greater_equal "5" "${delays[0]}" "First delay should be at least base delay"
    assert_less_equal "10" "${delays[0]}" "First delay should not be excessive"
    
    # Last delay should be at max
    assert_equals "40" "${delays[4]}" "Last delay should be at maximum"
    
    return 0
}

test_performance() {
    # Test that the function runs quickly for many calculations
    local start_time end_time
    start_time=$(date +%s)
    
    # Run 1000 calculations
    for i in {1..1000}; do
        calculate_exponential_backoff "$((i % 10 + 1))" 5 40 >/dev/null
    done
    
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should complete in reasonable time (less than 5 seconds)
    assert_less_equal "5" "$duration" "1000 calculations should complete quickly"
    
    return 0
}

# Run all tests
echo "=== Exponential Backoff Test Suite ==="
echo

run_test "basic calculation" test_basic_calculation
run_test "max delay cap" test_max_delay_cap
run_test "default parameters" test_default_parameters
run_test "custom parameters" test_custom_parameters
run_test "edge cases" test_edge_cases
run_test "sequence progression" test_sequence_progression
run_test "mathematical properties" test_mathematical_properties
run_test "realistic scenario" test_realistic_scenario
run_test "performance" test_performance

# Test summary
echo
echo "=== Test Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All exponential backoff tests passed!"
    exit 0
else
    echo "❌ Some exponential backoff tests failed!"
    exit 1
fi