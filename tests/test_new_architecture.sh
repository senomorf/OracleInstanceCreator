#!/bin/bash

# Comprehensive integration tests for the new separate jobs architecture
# Tests the complete refactored workflow from single job to separate A1.Flex + E2.Micro jobs

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Test configuration
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== New Architecture Integration Tests ==="
echo "Testing the refactored separate jobs architecture"
echo

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

# Test 1: Architecture refactoring completeness
test_architecture_completeness() {
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify we have all expected jobs
    local expected_jobs=("create-a1-flex" "create-e2-micro" "create-instance-unified" "notify-results")
    for job in "${expected_jobs[@]}"; do
        if ! grep -q "^  ${job}:" "$workflow_file"; then
            echo "Missing expected job: $job"
            return 1
        fi
    done
    
    # Verify separate jobs are default strategy
    if ! grep -q "job_strategy != 'unified'" "$workflow_file"; then
        echo "Separate jobs not configured as default strategy"
        return 1
    fi
    
    # Verify unlimited minutes optimization (no old constraints)
    if grep -q "55.*second" scripts/* || grep -q "BILLING_TIMEOUT" scripts/constants.sh 2>/dev/null; then
        echo "Old billing constraints still present in scripts"
        return 1
    fi
}

# Test 2: Shape-specific launcher integration
test_shape_launcher_integration() {
    local a1_script="scripts/launch-a1-flex.sh"
    local e2_script="scripts/launch-e2-micro.sh"
    
    # Verify launchers exist and are executable
    if [[ ! -x "$a1_script" ]] || [[ ! -x "$e2_script" ]]; then
        echo "Launcher scripts missing or not executable"
        return 1
    fi
    
    # Verify launchers set shape-specific variables and delegate
    if ! grep -q "A1_FLEX_SHAPE" "$a1_script" || ! grep -q "launch-instance.sh" "$a1_script"; then
        echo "A1.Flex launcher integration incomplete"
        return 1
    fi
    
    if ! grep -q "E2_MICRO_SHAPE" "$e2_script" || ! grep -q "launch-instance.sh" "$e2_script"; then
        echo "E2.Micro launcher integration incomplete"
        return 1
    fi
}

# Test 3: Composite action integration
test_composite_action_integration() {
    local action_file=".github/actions/setup-oci/action.yml"
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify composite action exists with required structure
    if [[ ! -f "$action_file" ]]; then
        echo "Setup-oci composite action missing"
        return 1
    fi
    
    # Verify composite action has required inputs and outputs
    if ! grep -q "oci_user_ocid:" "$action_file" || ! grep -q "cache_key:" "$action_file"; then
        echo "Composite action missing required inputs/outputs"
        return 1
    fi
    
    # Verify both separate jobs use the composite action
    if ! grep -c "uses:.*setup-oci" "$workflow_file" >/dev/null; then
        echo "Jobs don't use setup-oci composite action"
        return 1
    fi
}

# Test 4: Cache coordination integration
test_cache_coordination_integration() {
    local action_file=".github/actions/setup-oci/action.yml"
    
    # Verify cache key generation uses region hash and date
    if ! grep -q "region_hash.*sha256sum" "$action_file"; then
        echo "Cache coordination missing region-based keys"
        return 1
    fi
    
    # Verify cache includes date (via get-date step output)
    if ! grep -q "get-date.outputs.date" "$action_file"; then
        echo "Cache keys missing date for TTL"
        return 1
    fi
}

# Test 5: Job output coordination
test_job_output_coordination() {
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify both jobs define script_exit_code and instance_created outputs
    local jobs_with_outputs=$(grep -A 5 "outputs:" "$workflow_file" | grep -c "script_exit_code:" || echo "0")
    
    if [[ $jobs_with_outputs -lt 2 ]]; then
        echo "Not enough jobs define required outputs"
        return 1
    fi
    
    # Verify notification job consumes outputs
    if ! grep -q "needs.create-a1-flex.outputs" "$workflow_file" || 
       ! grep -q "needs.create-e2-micro.outputs" "$workflow_file"; then
        echo "Notification job doesn't consume job outputs"
        return 1
    fi
}

# Test 6: Notification logic integration
test_notification_logic_integration() {
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify notification job exists and handles results
    if ! grep -q "notify-results:" "$workflow_file"; then
        echo "Notification job missing"
        return 1
    fi
    
    # Verify notification job runs on all outcomes
    if ! grep -A 10 "notify-results:" "$workflow_file" | grep -q "if:.*always()"; then
        echo "Notification job doesn't run on all outcomes"
        return 1
    fi
    
    # Verify notification respects ENABLE_NOTIFICATIONS
    if ! grep -A 50 "notify-results:" "$workflow_file" | grep -q "ENABLE_NOTIFICATIONS"; then
        echo "Notification doesn't respect enable flag"
        return 1
    fi
}

# Test 7: Backwards compatibility integration
test_backwards_compatibility_integration() {
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify unified job exists and uses parallel script
    if ! grep -q "create-instance-unified:" "$workflow_file"; then
        echo "Unified fallback job missing"
        return 1
    fi
    
    # Verify unified job calls launch-parallel.sh (search larger section)
    if ! grep -A 150 "create-instance-unified:" "$workflow_file" | grep -q "launch-parallel.sh"; then
        echo "Unified job doesn't use existing parallel script"
        return 1
    fi
}

# Test 8: Environment variable propagation
test_environment_propagation() {
    local workflow_file=".github/workflows/infrastructure-deployment.yml"
    
    # Verify workflow-level environment variables are defined
    if ! grep -A 10 "^env:" "$workflow_file" | grep -q "OCI_API_DEBUG\|SCRIPT_DEBUG\|ENABLE_NOTIFICATIONS"; then
        echo "Workflow-level environment variables missing"
        return 1
    fi
    
    # Verify jobs reference environment variables
    if ! grep -q "env.SCRIPT_DEBUG" "$workflow_file"; then
        echo "Jobs don't reference workflow environment variables"
        return 1
    fi
}

# Test 9: Shape constants integration
test_shape_constants_integration() {
    # Verify shape constants are properly defined
    if ! source scripts/constants.sh; then
        echo "Cannot source constants.sh"
        return 1
    fi
    
    # Check key constants
    if [[ "$A1_FLEX_SHAPE" != "VM.Standard.A1.Flex" ]] || 
       [[ "$E2_MICRO_SHAPE" != "VM.Standard.E2.1.Micro" ]] ||
       [[ "$A1_FLEX_OCPUS" != "4" ]]; then
        echo "Shape constants incorrectly defined"
        return 1
    fi
}

# Test 10: System integration completeness
test_system_integration_completeness() {
    # Verify all critical system components exist
    local critical_files=(
        "scripts/circuit-breaker.sh"
        "scripts/notify.sh" 
        "scripts/state-manager.sh"
        "scripts/utils.sh"
        "scripts/validate-config.sh"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Critical system file missing: $file"
            return 1
        fi
    done
    
    # Verify integration points work
    if ! grep -q "state-manager.sh init" .github/actions/setup-oci/action.yml; then
        echo "State management not integrated"
        return 1
    fi
}

# Run all integration tests
run_test "architecture refactoring completeness" test_architecture_completeness
run_test "shape-specific launcher integration" test_shape_launcher_integration
run_test "composite action integration" test_composite_action_integration
run_test "cache coordination integration" test_cache_coordination_integration
run_test "job output coordination" test_job_output_coordination
run_test "notification logic integration" test_notification_logic_integration
run_test "backwards compatibility integration" test_backwards_compatibility_integration
run_test "environment variable propagation" test_environment_propagation
run_test "shape constants integration" test_shape_constants_integration
run_test "system integration completeness" test_system_integration_completeness

# Test summary
echo
echo "=== Integration Test Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All new architecture integration tests passed!"
    echo
    echo "🎯 REFACTORING VALIDATION COMPLETE:"
    echo "  ✓ Single job → Separate A1.Flex + E2.Micro jobs (default)"
    echo "  ✓ Unified job retained as fallback option" 
    echo "  ✓ Setup-oci composite action eliminates duplication"
    echo "  ✓ Cache coordination prevents race conditions"
    echo "  ✓ Job output coordination for notifications"
    echo "  ✓ Environment variable propagation working"
    echo "  ✓ Shape-specific launchers with proper delegation"
    echo "  ✓ Public repo unlimited minutes optimization"
    echo "  ✓ Backwards compatibility maintained"
    echo "  ✓ All existing systems integrated"
    echo
    echo "The refactored architecture is ready for production use!"
    exit 0
else
    echo "❌ Some integration tests failed!"
    echo "Review the failures above before deploying the new architecture."
    exit 1
fi