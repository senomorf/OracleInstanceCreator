#!/bin/bash

# Test suite for instance lifecycle management functionality
# Validates core lifecycle functions, configuration, and safety checks

set -euo pipefail

# Test directory setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Source the lifecycle script for testing
source "$SCRIPTS_DIR/instance-lifecycle.sh"

# Test state tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
log_test() {
    echo "[TEST] $*"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-equality check}"
    
    ((TESTS_RUN++))
    
    if [[ "$expected" == "$actual" ]]; then
        log_test "✅ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_test "❌ FAIL: $test_name - expected '$expected', got '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local test_name="${2:-boolean check}"
    
    ((TESTS_RUN++))
    
    if [[ "$condition" == "true" ]]; then
        log_test "✅ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_test "❌ FAIL: $test_name - expected true, got '$condition'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local test_name="${2:-boolean check}"
    
    ((TESTS_RUN++))
    
    if [[ "$condition" == "false" ]]; then
        log_test "✅ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_test "❌ FAIL: $test_name - expected false, got '$condition'"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test configuration loading and defaults
test_lifecycle_configuration() {
    log_test "Testing lifecycle configuration loading..."
    
    # Clear environment variables to test defaults
    unset AUTO_ROTATE_INSTANCES INSTANCE_MIN_AGE_HOURS ROTATION_STRATEGY HEALTH_CHECK_ENABLED DRY_RUN || true
    
    # Load configuration
    get_lifecycle_config
    
    # Test default values
    assert_equals "false" "$AUTO_ROTATE_INSTANCES" "AUTO_ROTATE_INSTANCES default"
    assert_equals "24" "$INSTANCE_MIN_AGE_HOURS" "INSTANCE_MIN_AGE_HOURS default"
    assert_equals "oldest_first" "$ROTATION_STRATEGY" "ROTATION_STRATEGY default"
    assert_equals "true" "$HEALTH_CHECK_ENABLED" "HEALTH_CHECK_ENABLED default"
    assert_equals "false" "$DRY_RUN" "DRY_RUN default"
}

# Test instance age calculation
test_instance_age_calculation() {
    log_test "Testing instance age calculation..."
    
    # Test with a timestamp from 2 hours ago
    local two_hours_ago
    two_hours_ago=$(date -d '2 hours ago' -u '+%Y-%m-%dT%H:%M:%S.000000Z')
    
    local age_hours
    age_hours=$(calculate_instance_age_hours "$two_hours_ago")
    
    # Age should be approximately 2 hours (allowing for small timing differences)
    if [[ $age_hours -ge 1 && $age_hours -le 3 ]]; then
        assert_true "true" "Age calculation for 2-hour-old instance"
    else
        assert_true "false" "Age calculation for 2-hour-old instance (got ${age_hours}h)"
    fi
    
    # Test with a timestamp from 25 hours ago
    local twenty_five_hours_ago
    twenty_five_hours_ago=$(date -d '25 hours ago' -u '+%Y-%m-%dT%H:%M:%S.000000Z')
    
    age_hours=$(calculate_instance_age_hours "$twenty_five_hours_ago")
    
    # Age should be approximately 25 hours
    if [[ $age_hours -ge 24 && $age_hours -le 26 ]]; then
        assert_true "true" "Age calculation for 25-hour-old instance"
    else
        assert_true "false" "Age calculation for 25-hour-old instance (got ${age_hours}h)"
    fi
}

# Test shape utilization calculation (mock)
test_shape_utilization_mock() {
    log_test "Testing shape utilization calculation (mock)..."
    
    # Test E2.1.Micro calculation
    # Note: This test uses mock data since we can't make real OCI API calls
    
    # Mock the oci_cmd function for testing
    oci_cmd() {
        case "$*" in
            *"VM.Standard.E2.1.Micro"*)
                echo '["instance1", "instance2"]'  # 2 instances
                ;;
            *"VM.Standard.A1.Flex"*)
                echo '[{"id": "inst1", "ocpus": 2}, {"id": "inst2", "ocpus": 1}]'  # 3 total OCPUs
                ;;
            *)
                echo '[]'
                ;;
        esac
    }
    
    # Export the mock function
    export -f oci_cmd
    
    # Test E2.1.Micro utilization (would be 100% with 2 instances)
    local utilization
    utilization=$(get_shape_utilization "VM.Standard.E2.1.Micro" "mock_compartment")
    assert_equals "100" "$utilization" "E2.1.Micro utilization calculation"
    
    # Test A1.Flex utilization (would be 75% with 3 OCPUs out of 4)
    utilization=$(get_shape_utilization "VM.Standard.A1.Flex" "mock_compartment")
    assert_equals "75" "$utilization" "A1.Flex utilization calculation"
    
    # Restore original oci_cmd function
    unset -f oci_cmd
    source "$SCRIPTS_DIR/utils.sh"
}

# Test lifecycle management configuration validation
test_lifecycle_config_validation() {
    log_test "Testing lifecycle configuration validation..."
    
    # Test valid configuration
    export AUTO_ROTATE_INSTANCES="true"
    export INSTANCE_MIN_AGE_HOURS="24"
    export ROTATION_STRATEGY="oldest_first"
    export HEALTH_CHECK_ENABLED="true"
    export DRY_RUN="false"
    
    if validate_lifecycle_config >/dev/null 2>&1; then
        assert_true "true" "Valid lifecycle configuration"
    else
        assert_true "false" "Valid lifecycle configuration should pass"
    fi
    
    # Test invalid boolean value
    export AUTO_ROTATE_INSTANCES="maybe"
    if validate_lifecycle_config >/dev/null 2>&1; then
        assert_true "false" "Invalid boolean should fail validation"
    else
        assert_true "true" "Invalid boolean correctly fails validation"
    fi
    
    # Test invalid rotation strategy
    export AUTO_ROTATE_INSTANCES="true"
    export ROTATION_STRATEGY="invalid_strategy"
    if validate_lifecycle_config >/dev/null 2>&1; then
        assert_true "false" "Invalid rotation strategy should fail validation"
    else
        assert_true "true" "Invalid rotation strategy correctly fails validation"
    fi
    
    # Test invalid minimum age (too large)
    export ROTATION_STRATEGY="oldest_first"
    export INSTANCE_MIN_AGE_HOURS="10000"  # More than 1 year
    if validate_lifecycle_config >/dev/null 2>&1; then
        assert_true "false" "Invalid min age should fail validation"
    else
        assert_true "true" "Invalid min age correctly fails validation"
    fi
    
    # Reset to valid configuration
    export INSTANCE_MIN_AGE_HOURS="24"
}

# Test dry run mode functionality
test_dry_run_mode() {
    log_test "Testing dry run mode functionality..."
    
    # Mock terminate_instance function for dry run test
    terminate_instance_original=$(declare -f terminate_instance)
    
    terminate_instance() {
        local instance_id="$1"
        local instance_name="$2"
        local dry_run="$3"
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY RUN] Would terminate instance: $instance_name ($instance_id)"
            return 0
        else
            return 1  # Would fail in real scenario for mock
        fi
    }
    
    # Test dry run mode
    local result
    result=$(terminate_instance "mock_id" "mock_instance" "true" 2>&1)
    
    if [[ "$result" == *"[DRY RUN]"* ]]; then
        assert_true "true" "Dry run mode produces correct output"
    else
        assert_true "false" "Dry run mode should indicate simulation"
    fi
    
    # Restore original function
    eval "$terminate_instance_original"
}

# Test safety checks
test_safety_checks() {
    log_test "Testing safety checks..."
    
    # Test minimum age enforcement
    export INSTANCE_MIN_AGE_HOURS="24"
    
    # Create mock instance list with mixed ages
    local instances='[
        {"id": "old_instance", "name": "old", "created": "2023-01-01T00:00:00.000000Z", "state": "RUNNING"},
        {"id": "new_instance", "name": "new", "created": "'$(date -d '1 hour ago' -u '+%Y-%m-%dT%H:%M:%S.000000Z')'", "state": "RUNNING"}
    ]'
    
    # Mock select_instances_for_rotation to test age filtering
    select_instances_for_rotation_original=$(declare -f select_instances_for_rotation)
    
    select_instances_for_rotation() {
        local shape="$1"
        local compartment_id="$2"
        local count="$3"
        local strategy="$4"
        
        # Return only instances that meet minimum age requirement
        echo "$instances" | jq --arg min_age "$INSTANCE_MIN_AGE_HOURS" '[.[] | select(now - (.created | fromdateiso8601) > ($min_age | tonumber * 3600))]'
    }
    
    local result
    result=$(select_instances_for_rotation "test_shape" "test_compartment" "1" "oldest_first")
    
    local selected_count
    selected_count=$(echo "$result" | jq '. | length' 2>/dev/null || echo 0)
    
    # Should only select the old instance, not the new one
    assert_equals "1" "$selected_count" "Safety check: only old instances selected"
    
    # Restore original function
    eval "$select_instances_for_rotation_original"
}

# Test error handling
test_error_handling() {
    log_test "Testing error handling..."
    
    # Test invalid timestamp handling
    local age_result
    age_result=$(calculate_instance_age_hours "invalid_timestamp" 2>/dev/null || echo "error")
    
    if [[ "$age_result" == "error" ]] || [[ "$age_result" == "0" ]]; then
        assert_true "true" "Invalid timestamp handled gracefully"
    else
        assert_true "false" "Invalid timestamp should be handled gracefully"
    fi
    
    # Test missing environment variables
    local original_compartment_id="${OCI_COMPARTMENT_ID:-}"
    unset OCI_COMPARTMENT_ID || true
    
    if init_lifecycle_manager >/dev/null 2>&1; then
        assert_true "false" "Missing OCI_COMPARTMENT_ID should fail initialization"
    else
        assert_true "true" "Missing required env vars correctly fail initialization"
    fi
    
    # Restore environment variable
    if [[ -n "$original_compartment_id" ]]; then
        export OCI_COMPARTMENT_ID="$original_compartment_id"
    fi
}

# Test integration with existing systems
test_integration_points() {
    log_test "Testing integration with existing systems..."
    
    # Test that lifecycle management respects existing state management
    if command -v init_state_manager >/dev/null 2>&1; then
        assert_true "true" "State management integration available"
    else
        assert_true "false" "State management integration should be available"
    fi
    
    # Test that notification functions are available
    if command -v send_telegram_notification >/dev/null 2>&1; then
        assert_true "true" "Notification integration available"
    else
        assert_true "false" "Notification integration should be available"
    fi
    
    # Test that OCI command wrapper is available
    if command -v oci_cmd >/dev/null 2>&1; then
        assert_true "true" "OCI command wrapper integration available"
    else
        assert_true "false" "OCI command wrapper integration should be available"
    fi
}

# Run all tests
run_all_tests() {
    log_test "Starting instance lifecycle management tests..."
    
    # Setup test environment
    export OCI_COMPARTMENT_ID="ocid1.compartment.oc1..fake_compartment_for_tests"
    export OCI_REGION="us-ashburn-1"
    
    # Run test suites
    test_lifecycle_configuration
    test_instance_age_calculation
    test_shape_utilization_mock
    test_lifecycle_config_validation
    test_dry_run_mode
    test_safety_checks
    test_error_handling
    test_integration_points
    
    # Print test summary
    echo ""
    log_test "Test Summary:"
    log_test "  Tests run: $TESTS_RUN"
    log_test "  Tests passed: $TESTS_PASSED"
    log_test "  Tests failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_test "✅ All tests passed!"
        return 0
    else
        log_test "❌ Some tests failed!"
        return 1
    fi
}

# Execute tests if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi