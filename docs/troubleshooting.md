# Oracle Instance Creator - Troubleshooting Guide

This comprehensive runbook helps diagnose and resolve common issues with the Oracle Instance Creator.

## Quick Diagnostic Checklist

Before diving into specific issues, run through this checklist:

1. **Run Preflight Check**: `./scripts/preflight-check.sh`
2. **Run Integration Tests**: `./tests/test_parallel_execution.sh`
3. **Check Recent Logs**: Look for error patterns in GitHub Actions logs
4. **Verify Timing**: Check if execution time is within expected range (17-20 seconds)
5. **Review Notifications**: Check Telegram for error details
6. **Test Signal Handling**: `./tests/test_signal_handling.sh`

## Common Issues and Solutions

### 🔐 Authentication & Configuration Issues

#### Problem: "Invalid credentials" or "Authentication failed"
**Symptoms:**
- Preflight check fails on OCI connectivity test
- Error messages containing "401 Unauthorized"
- Critical Telegram notifications about authentication

**Diagnosis:**
```bash
# Test OCI authentication manually
oci iam user get --user-id $OCI_USER_OCID
```

**Solutions:**
1. **Verify GitHub Secrets**:
   - `OCI_USER_OCID`: Must be your user's OCID, not tenancy OCID
   - `OCI_TENANCY_OCID`: Your tenancy OCID from OCI console
   - `OCI_KEY_FINGERPRINT`: Must match your API key fingerprint exactly
   - `OCI_PRIVATE_KEY`: Complete private key including header/footer

2. **Check API Key Status**:
   - Ensure API key is active in OCI Console → User Settings → API Keys
   - Verify key hasn't expired
   - Check if user has required permissions

3. **Regional Settings**:
   - Ensure `OCI_REGION` matches where your resources are located
   - Some resources might be region-specific

#### Problem: "Invalid OCID format"
**Symptoms:**
- Preflight check fails on OCID validation
- Error messages about malformed OCIDs
- Configuration errors in Telegram notifications

**Solutions:**
1. **Verify OCID Format**:
   ```bash
   # Valid OCID format: ocid1.<resource-type>.<realm>.<region>.<unique-id>
   # Example: ocid1.user.oc1..aaaaaaaaexample123456789
   ```

2. **Common OCID Issues**:
   - Extra spaces or newlines in GitHub secrets
   - Mixing up user OCID with tenancy OCID
   - Using resource names instead of OCIDs
   - Copying OCIDs from wrong regions

3. **Find Correct OCIDs**:
   ```bash
   # Get your user OCID
   oci iam user list --name "your-username"
   
   # Get compartment OCIDs
   oci iam compartment list --compartment-id-in-subtree true
   
   # Get subnet OCIDs
   oci network subnet list --compartment-id <compartment-ocid>
   ```

### 🚀 Instance Launch Issues

#### Problem: "Out of host capacity" (Most Common)
**Symptoms:**
- Workflow completes successfully (this is expected!)
- No instance created
- Log messages about trying different ADs
- CAPACITY error classification

**Understanding:**
This is **NOT a failure** - it's Oracle's normal response when free tier capacity is unavailable.

**Solutions:**
1. **Multi-AD Configuration** (Recommended):
   ```yaml
   OCI_AD: "AD-1,AD-2,AD-3"  # Try multiple domains
   ```

2. **Try Different Regions**:
   - Singapore: Often good availability
   - US regions: Can be busier
   - European regions: Mixed availability

3. **Peak Time Avoidance**:
   - Avoid business hours in target region
   - Try early morning or late evening UTC
   - Weekends sometimes have better availability

4. **ARM vs AMD Strategy**:
   ```yaml
   # ARM instances often more available
   OCI_SHAPE: "VM.Standard.A1.Flex"
   OCI_OCPUS: "4"
   OCI_MEMORY_IN_GBS: "24"
   
   # AMD instances - limited but sometimes available
   OCI_SHAPE: "VM.Standard.E2.1.Micro"
   # No OCPUS/MEMORY needed for fixed shapes
   ```

#### Problem: "Service limit exceeded" or "LimitExceeded"
**Symptoms:**
- Error about exceeding service limits
- May succeed despite error (verification system handles this)

**Solutions:**
1. **Check Existing Resources**:
   ```bash
   # Check current instances
   oci compute instance list --compartment-id <compartment-ocid>
   
   # Check resource limits
   oci limits resource-availability get --compartment-id <compartment-ocid>
   ```

2. **Free Tier Limits**:
   - ARM: 1 instance, 4 OCPUs total, 24 GB RAM total
   - AMD: 2 instances, 1 OCPU each, 1 GB RAM each
   - Block Storage: 200 GB total

3. **Clean Up Resources**:
   - Terminate unused instances
   - Delete unused boot volumes
   - Check compute instance pools

#### Problem: "User limit reached" (Exit Code 5)
**Expected Behavior:** NOT a failure - intelligent limit detection working correctly.

**Solutions:**
```bash
# Check status
./scripts/state-manager.sh limit-status

# Clear cache (after terminating instances)  
./scripts/state-manager.sh clear-limits
```

#### Problem: "Shape not supported in availability domain"
**Symptoms:**
- Specific error about shape availability
- Different ADs work with same shape

**Solutions:**
1. **Check Shape Availability**:
   ```bash
   oci compute shape list --compartment-id <compartment-ocid> --availability-domain <ad-name>
   ```

2. **Use Multi-AD Configuration**:
   - Different shapes available in different ADs
   - Multi-AD cycling finds compatible AD automatically

3. **Alternative Shapes**:
   ```yaml
   # If A1.Flex unavailable, try:
   OCI_SHAPE: "VM.Standard.E2.1.Micro"
   
   # For paid accounts:
   OCI_SHAPE: "VM.Standard3.Flex"
   ```

### ⚡ Performance Issues

#### Problem: Workflow takes too long (>30 seconds)
**Symptoms:**
- Execution time over 30 seconds
- Timeouts in logs
- Performance degradation from baseline

**Diagnosis:**
Check for these performance indicators in logs:
```
# Good performance (17-18 seconds):
[INFO] Instance launch completed in 17.234 seconds

# Poor performance (>30 seconds indicates issues):
[INFO] Instance launch completed in 67.891 seconds
```

**Solutions:**
1. **Verify OCI CLI Optimizations**:
   ```bash
   # Look for these flags in logs:
   --no-retry --connection-timeout 5 --read-timeout 15
   ```

2. **Network Issues**:
   - Check GitHub Actions service status
   - Verify OCI service health in your region
   - Consider different retry timing

3. **Missing Optimizations**:
   - Ensure latest version with performance flags
   - Check if exponential backoff was re-enabled accidentally

## Testing and Validation

### 🧪 Running the Test Suite

The project includes comprehensive tests for critical functionality:

#### Integration Tests
```bash
# Run full integration test suite
./tests/test_parallel_execution.sh

# Test specific components
source scripts/utils.sh
wait_for_result_file "/tmp/test_file" 5  # Test race condition fixes
mask_credentials "http://user:pass@proxy:8080"  # Test credential masking
validate_availability_domain "test:US-REGION-AD-1,test:US-REGION-AD-2"  # Test AD validation
```

#### Signal Handling Tests
```bash
# Test graceful shutdown behavior
./tests/test_signal_handling.sh

# Manual signal test
./scripts/launch-parallel.sh &
PID=$!
sleep 5
kill -TERM $PID  # Should cleanup gracefully
```

#### AD Cycling Tests  
```bash
# Test multi-AD failover logic
./tests/test_ad_cycling.sh

# Manual AD cycling test
export OCI_AD="test:AD-1,test:AD-2,test:AD-3"
export DEBUG=true
./scripts/launch-instance.sh
```

### 🔧 Validation Commands

#### Configuration Validation
```bash
# Enhanced validation with new checks
./scripts/validate-config.sh

# Test timeout value validation
source scripts/utils.sh
validate_timeout_value "TEST_TIMEOUT" "30" 5 300

# Test proxy URL validation (new enhanced format checking)
export OCI_PROXY_URL="user:pass@proxy.com:8080"
./scripts/validate-config.sh  # Should pass

export OCI_PROXY_URL="invalid-format"
./scripts/validate-config.sh  # Should fail with clear error
```

#### Error Handling Validation
```bash
# Test standardized error codes
source scripts/utils.sh
get_exit_code_for_error_type "USER_LIMIT_REACHED"  # Should return 5
get_exit_code_for_error_type "CAPACITY"            # Should return 2
get_exit_code_for_error_type "AUTH"                # Should return 3
get_exit_code_for_error_type "NETWORK"             # Should return 4
get_exit_code_for_error_type "UNKNOWN"             # Should return 1
```

### 📊 Performance Monitoring

#### Check Optimization Flags
```bash
# Verify critical performance optimizations are active
export DEBUG=true
./scripts/launch-parallel.sh 2>&1 | grep "Executing OCI debug command"
# Should show: --no-retry --connection-timeout 5 --read-timeout 15
```

#### Monitor Race Conditions  
```bash
# Test result file handling (should complete in <1 second)
source scripts/utils.sh
echo "test" > /tmp/race_test &
time wait_for_result_file "/tmp/race_test" 10
# Should find file almost immediately
```

#### Test Constants Usage
```bash
# Verify magic numbers have been replaced with constants
grep -n "55\|124\|077" scripts/launch-parallel.sh
# Should show references to constants, not magic numbers
```

#### Problem: Instance verification timeouts
**Symptoms:**
- "Instance verification failed after X checks"
- Instance exists but wasn't detected
- Longer provisioning times

**Solutions:**
1. **Increase Timeout**:
   ```yaml
   INSTANCE_VERIFY_MAX_CHECKS: "10"  # More attempts
   INSTANCE_VERIFY_DELAY: "45"       # Longer delays
   ```

2. **Check Instance State**:
   ```bash
   # Manual verification
   oci compute instance list --compartment-id <compartment-ocid> --display-name <instance-name>
   ```

3. **Regional Variations**:
   - Some regions provision slower
   - Larger instances take more time
   - Network connectivity affects timing

### 📱 Telegram Notification Issues

#### Problem: No Telegram notifications received
**Symptoms:**
- No messages from bot
- Preflight check passes but no notifications during workflow

**Solutions:**
1. **Verify Bot Configuration**:
   ```bash
   # Test bot token
   curl -s "https://api.telegram.org/bot<token>/getMe"
   
   # Get your user ID
   curl -s "https://api.telegram.org/bot<token>/getUpdates"
   ```

2. **Common Issues**:
   - Bot not started (send `/start` to bot)
   - Wrong user ID (use numeric ID, not username)
   - Bot blocked or deleted
   - Token typos in GitHub secrets

3. **Test Notifications**:
   ```bash
   # Manual test
   ./scripts/notify.sh test
   ```

#### Problem: Wrong notification severity levels
**Symptoms:**
- All notifications show as same priority
- Missing critical alerts
- Too many low-priority notifications

**Solutions:**
1. **Review Severity Mapping**:
   - 🚨 Critical: Authentication, configuration failures
   - ❌ Error: Launch failures, system errors  
   - ⚠️ Warning: Capacity issues, rate limits
   - ℹ️ Info: Status updates, successes
   - ✅ Success: Instance creation, completion

2. **Adjust Notification Settings**:
   - Use different bots for different severities
   - Configure notification rules based on emojis
   - Set up Telegram notification groups

### 🔍 Debug Mode and Logging

#### Enabling Debug Mode
For detailed troubleshooting, enable debug logging:

```yaml
# In GitHub Actions workflow
DEBUG: "true"
LOG_FORMAT: "json"  # For structured logs
```

#### Reading Debug Output
```bash
# Key debug patterns to look for:
[DEBUG] Executing OCI debug command: oci --no-retry...
[DEBUG] Using jq for JSON parsing to extract instance OCID
[DEBUG] Successfully extracted and validated instance OCID
```

#### Log Analysis Tips
1. **Timing Analysis**:
   ```
   Good: [INFO] Instance launch completed in 17.234 seconds
   Poor: [INFO] Instance launch completed in 67.891 seconds
   ```

2. **Error Pattern Recognition**:
   ```
   CAPACITY: Expected, will retry on schedule
   AUTH: Critical, needs immediate attention
   CONFIG: Critical, check configuration
   ```

3. **AD Success Tracking**:
   ```
   [INFO] AD-1: 100% success (2/2 attempts)
   [INFO] AD-2: 0% success (0/3 attempts)
   ```

## Recent Improvements Troubleshooting

### 🔧 Constants Consolidation Issues

After the constants consolidation update, you might encounter these issues:

#### Problem: "GITHUB_ACTIONS_TIMEOUT_SECONDS: unbound variable"
**Cause:** Old constant names still in use after centralization to `constants.sh`

**Solution:**
1. **Verify constants.sh is sourced**:
   ```bash
   grep -n "constants.sh" scripts/utils.sh scripts/launch-parallel.sh
   # Should show constants.sh being sourced
   ```

2. **Check for old constant references**:
   ```bash
   # These should return no results (old constants removed)
   grep -r "TIMEOUT_EXIT_CODE" scripts/
   grep -r "GITHUB_ACTIONS_TIMEOUT_SECONDS" scripts/
   
   # These should show new constants being used
   grep -r "EXIT_TIMEOUT_ERROR" scripts/
   grep -r "GITHUB_ACTIONS_BILLING_TIMEOUT" scripts/
   ```

3. **Validate constants are loaded**:
   ```bash
   # Test constants validation
   ./scripts/validate-config.sh
   # Should show "Constants configuration validation passed"
   ```

#### Problem: Functions like `wait_for_result_file` fail
**Cause:** Constants name mismatch after consolidation

**Solution:**
```bash
# Verify constants mapping in constants.sh
grep -A 5 -B 5 "RESULT_FILE" scripts/constants.sh
# Should show: RESULT_FILE_WAIT_TIMEOUT and RESULT_FILE_POLL_INTERVAL

# Test the function directly
source scripts/utils.sh
temp_file=$(mktemp)
echo "test" > "$temp_file"
wait_for_result_file "$temp_file" 5  # Should succeed immediately
```

### 🧪 New Integration Test Issues

#### Problem: New tests failing in `test_integration.sh`
**Symptoms:**
- "Network partition simulation" fails
- "Concurrent execution stress" fails
- Tests timeout or show race conditions

**Diagnosis:**
```bash
# Run individual tests with debug
DEBUG=true ./tests/test_integration.sh

# Check for race conditions in stress test
for i in {1..5}; do
  echo "Run $i:"
  ./tests/test_integration.sh | grep -E "(stress|concurrent)"
done
```

**Solutions:**
1. **Increase timeout for slower systems**:
   ```bash
   # Edit test_integration.sh, increase MOCK_DURATION if needed
   # Default is 3 seconds, try 5 for slower systems
   ```

2. **Check file system performance**:
   ```bash
   # Test file creation speed (should be <1ms)
   time (echo "test" > /tmp/speed_test.txt)
   rm -f /tmp/speed_test.txt
   ```

### 🔍 Configuration Validation Enhancement Issues

#### Problem: New validation checks failing
**Symptoms:**
- "Constants validation failed"
- "GITHUB_ACTIONS_BILLING_TIMEOUT must be less than boundary"
- Validation errors for transient retry settings

**Solutions:**
1. **Check constants.sh values**:
   ```bash
   grep -E "BILLING_TIMEOUT|BILLING_BOUNDARY" scripts/constants.sh
   # Timeout should be less than boundary (55 < 60)
   ```

2. **Validate retry configuration**:
   ```bash
   # Check retry bounds in constants.sh
   grep -A 3 -B 3 "TRANSIENT_ERROR.*RETRIES" scripts/constants.sh
   # Default should be between MIN and MAX values
   ```

3. **Test validation manually**:
   ```bash
   source scripts/constants.sh
   source scripts/utils.sh
   validate_constants_configuration  # New function
   ```

### 🚀 Parallel Execution Improvements

#### Problem: Parallel execution behaves differently after updates
**Symptoms:**
- Different timing patterns
- New error messages
- Changed exit codes

**Expected Changes (Normal):**
- More consistent timeout handling (55 seconds exactly)
- Better process cleanup (no zombie processes)
- Improved error classification
- Enhanced result file handling

**Validation:**
```bash
# Test timing consistency (should be ~20-25 seconds for capacity errors)
time ./scripts/launch-parallel.sh

# Check process cleanup (no OCI processes should remain)
ps aux | grep -i oci | grep -v grep

# Verify result files are cleaned up
ls -la /tmp/ | grep -E "(a1_result|e2_result)" # Should be empty
```

## Advanced Troubleshooting

### Network Connectivity Issues
```bash
# Test OCI connectivity
curl -I https://identity.ap-singapore-1.oraclecloud.com/

# Test GitHub Actions connectivity
# (This runs automatically in workflow)
```

### Resource Limit Analysis
```bash
# Check all limits
oci limits resource-availability get --compartment-id <compartment-ocid> --service-name compute

# Specific limit for free tier
oci limits value list --compartment-id <compartment-ocid> --service-name compute | grep -i "standard-a1-core-count"
```

### Image Compatibility Issues
```bash
# List compatible images for your shape
oci compute image list --compartment-id <tenancy-ocid> --operating-system "Oracle Linux" --shape <shape-name>

# Check image availability in specific AD
oci compute image list --compartment-id <tenancy-ocid> --operating-system "Oracle Linux" --sort-by TIMECREATED --sort-order DESC
```

## Performance Monitoring

### Expected Metrics
- **Total Execution Time**: 17-20 seconds
- **OCI CLI Operations**: <2 seconds each
- **Instance Verification**: <60 seconds total
- **Multi-AD Cycling**: <30 seconds per AD

### Warning Thresholds
- **Execution Time >30 seconds**: Check network/config
- **Verification >120 seconds**: Increase timeout
- **Multiple AUTH failures**: Check credentials immediately

## Getting Help

### Log Collection
When requesting help, include:
1. **Preflight check output**
2. **GitHub Actions logs** (last 50 lines)
3. **Configuration template used**
4. **Telegram notification screenshots**
5. **Timing information from logs**

### Common Log Locations
- GitHub Actions: Repository → Actions → Workflow run
- Local testing: Terminal output with `DEBUG=true`
- Telegram: Bot messages with severity indicators

### Support Channels
1. **GitHub Issues**: For bugs and feature requests
2. **Configuration Help**: Use preflight check first
3. **Performance Issues**: Include timing logs
4. **Authentication Problems**: Never share private keys!

## Prevention

### Best Practices
1. **Always run preflight check** before deployment
2. **Use multi-AD configuration** for better success rates
3. **Monitor execution times** for performance regression
4. **Test configuration changes** in non-production first
5. **Keep image caches updated** periodically

### Regular Maintenance
- Update cached image OCIDs monthly
- Review AD success metrics weekly  
- Test Telegram notifications monthly
- Check for new Oracle regions/shapes quarterly

### Security Checklist
- ✅ No private keys in logs
- ✅ OCIDs properly redacted in debug output
- ✅ GitHub secrets configured correctly
- ✅ API key rotation schedule in place
- ✅ Telegram bot security configured

---

*This troubleshooting guide is comprehensive but if you encounter new issues, please update this document and share with the community.*