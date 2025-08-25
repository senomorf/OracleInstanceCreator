# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Oracle Cloud Infrastructure (OCI) automation project that uses GitHub Actions to automatically attempt creating **BOTH** Oracle Cloud free tier instances simultaneously. The project is designed to periodically retry instance creation for both ARM (A1.Flex) and AMD (E2.1.Micro) shapes when Oracle's free tier capacity is available, maximizing your chances of securing free tier resources.

## Architecture

The project has been refactored into a modular architecture with the following components:

### File Structure
```
├── .github/workflows/free-tier-creation.yml  # GitHub Actions workflow (parallel execution)
├── scripts/
│   ├── setup-oci.sh                          # OCI CLI configuration
│   ├── setup-ssh.sh                          # SSH key setup  
│   ├── validate-config.sh                    # Configuration validation
│   ├── launch-parallel.sh                    # Parallel launcher for both shapes
│   ├── launch-instance.sh                    # Shape-agnostic instance creation logic
│   ├── notify.sh                             # Telegram notifications
│   └── utils.sh                              # Common utility functions
├── config/
│   ├── instance-profiles.yml                 # Pre-defined configurations
│   ├── defaults.yml                          # Default values and validation
│   └── regions.yml                           # Region reference data
└── docs/
    └── configuration.md                       # Comprehensive documentation
```

### Workflow Jobs

The GitHub Actions workflow consists of two secure jobs optimized for billing efficiency:

1. **create-instances** (Both Shapes): Validates configuration, sets up environment, and attempts to create BOTH free tier instance shapes in parallel within a single job to minimize GitHub Actions billing
2. **notify-on-failure**: Sends failure notifications if both instance creation attempts fail

**Key Features:**
- **Parallel Execution**: Both ARM (A1.Flex) and AMD (E2.1.Micro) shapes attempted simultaneously
- **Billing Optimization**: Single job execution stays under 60 seconds to avoid 2-minute billing
- **Security Enhancement**: All credential operations occur within a single job to prevent exposure through artifacts
- **Timeout Protection**: 55-second timeout ensures billing stays at 1 minute per run

## Key Configuration

### Parallel Shape Configuration

The workflow automatically attempts to create BOTH free tier instance shapes:

**A1.Flex (ARM) Configuration:**
- **Shape**: VM.Standard.A1.Flex
- **OCPUs**: 4
- **Memory**: 24GB
- **Instance Name**: a1-flex-sg

**E2.1.Micro (AMD) Configuration:**
- **Shape**: VM.Standard.E2.1.Micro  
- **OCPUs**: 1 (fixed shape)
- **Memory**: 1GB (fixed shape)
- **Instance Name**: e2-micro-sg

### Common Environment Variables

- **OCI_AD**: Availability Domain (e.g., "fgaj:AP-SINGAPORE-1-AD-1")
- **OPERATING_SYSTEM**: OS name (e.g., "Oracle Linux") 
- **OS_VERSION**: OS version (e.g., "9")
- **ASSIGN_PUBLIC_IP**: Public IP assignment ("false" by default)

## Required GitHub Secrets

The workflow requires these secrets to be configured in the GitHub repository:

- **OCI_USER_OCID**: Oracle user OCID
- **OCI_KEY_FINGERPRINT**: API key fingerprint  
- **OCI_TENANCY_OCID**: Tenancy OCID
- **OCI_REGION**: OCI region
- **OCI_PRIVATE_KEY**: Private API key content
- **OCI_COMPARTMENT_ID**: Compartment OCID (optional, uses tenancy if not set)
- **OCI_SUBNET_ID**: Subnet OCID
- **OCI_IMAGE_ID**: Image OCID (optional, auto-detected if not set)
- **INSTANCE_SSH_PUBLIC_KEY**: SSH public key for instance access
- **TELEGRAM_TOKEN**: Telegram bot token for notifications
- **TELEGRAM_USER_ID**: Telegram user ID for notifications

## Workflow Execution

The workflow can be triggered:

- **Manually**: Via workflow_dispatch with optional verbose output
- **Scheduled**: Every 6 minutes (`*/6 * * * *`) to maximize free tier opportunities

### Parallel Execution Behavior

**Success Scenarios:**
- **Both instances created**: Maximum free tier utilization achieved
- **One instance created**: Partial success - will retry for the other shape on next run
- **Zero instances created**: Capacity unavailable - will retry on next scheduled run

**Timing Optimization:**
- **Target execution time**: 17-25 seconds (both shapes in parallel)
- **Timeout safety**: 55-second hard limit to prevent 2-minute billing
- **GitHub Actions billing**: 1 minute per run (instead of 2 minutes with matrix jobs)

### Billing Efficiency

**Monthly Usage Calculation** (every 6 minutes):
- **Runs per day**: 240 (every 6 minutes)
- **Runs per month**: ~7,200
- **Billing per run**: 1 minute (single job under 60 seconds)
- **Total monthly usage**: 7,200 minutes (exceeds GitHub free tier of 2,000 minutes)

**Cost Optimization Options:**
1. **Accept billing**: ~$52/month for maximum attempts
2. **Reduce frequency**: Every 15 minutes = 2,880 minutes/month (near free tier)
3. **Reduce frequency**: Every 20 minutes = 2,160 minutes/month (within free tier buffer)

## Error Handling

The workflow implements intelligent error handling:

- **Capacity Issues**: Treated as non-failures, allowing for retry attempts
- **Configuration Errors**: Send Telegram alerts and fail the workflow
- **Duplicate Prevention**: Checks for existing instances before creation
- **Notification System**: Uses Telegram for success and error notifications

## Development Commands

The refactored project supports both GitHub Actions execution and local testing:

### GitHub Actions Workflow
```bash
# Validate workflow syntax
cat .github/workflows/free-tier-creation.yml
```

### Local Script Testing
```bash
# Make all scripts executable
chmod +x scripts/*.sh

# Test individual components (requires environment variables)
./scripts/validate-config.sh      # Validate configuration
./scripts/setup-oci.sh           # Setup OCI authentication
./scripts/setup-ssh.sh           # Setup SSH keys
./scripts/launch-parallel.sh     # Launch both shapes in parallel
./scripts/launch-instance.sh     # Launch single shape (with env vars set)
./scripts/notify.sh test         # Test Telegram notifications

# Check script syntax
bash -n scripts/*.sh
```

### Configuration Management
```bash
# View available instance profiles
cat config/instance-profiles.yml

# Check default values and validation rules
cat config/defaults.yml

# Reference region information
cat config/regions.yml
```

## Important Notes

- **Parallel Free Tier Maximization**: Simultaneously attempts both ARM (A1.Flex) and AMD (E2.1.Micro) free tier shapes to maximize Oracle Cloud resource acquisition
- **GitHub Actions Billing Optimization**: Single-job architecture keeps billing at 1 minute per run, avoiding the 2x cost of matrix jobs
- **Timeout Protection**: Built-in 55-second timeout prevents accidental 2-minute billing charges
- **Enhanced Testability**: Individual scripts can be tested locally without GitHub Actions
- **Improved Error Handling**: Comprehensive error classification with intelligent retry logic and notifications  
- **Shape-Agnostic Architecture**: Core instance creation logic works with any OCI shape configuration
- **Backward Compatibility**: All existing GitHub secrets and functionality are preserved
- **Better Maintainability**: Clear separation of concerns makes the system easier to understand and modify

## Critical Technical Patterns (Lessons Learned)

### Parallel Execution Implementation (Added 2025-08-25)

**Key Decision: Single Job vs Matrix Strategy**
- **Chosen**: Single job with background processes (`&` and `wait`)
- **Avoided**: GitHub Actions matrix strategy due to billing implications
- **Reasoning**: Matrix jobs are billed separately (2 jobs × 1 min = 2 minutes vs 1 job × 1 min = 1 minute)
- **Implementation**: `scripts/launch-parallel.sh` orchestrates parallel execution within single job

**Timeout Strategy for Billing Control**
- **Critical insight**: GitHub Actions rounds each job UP to nearest minute
- **Solution**: 55-second hard timeout to prevent 2-minute billing
- **Method**: `timeout` command with process cleanup on exceed
- **Result**: Guaranteed 1-minute billing regardless of execution time

**Shape-Agnostic Architecture Pattern**
- **Problem**: Needed to support both A1.Flex and E2.1.Micro with different configurations
- **Solution**: Environment variable injection per shape via subshells
- **Benefits**: Single `launch-instance.sh` handles all shapes, easy to add new shapes
- **Pattern**: `(export VAR=value; ./script.sh) &` for parallel execution

### Command Substitution + Logging Anti-Pattern
- **NEVER** use stdout in logging functions when called via `$()`
- **Solution**: Always redirect logging to stderr: `echo "message" >&2`
- **Impact**: Prevents log text injection into CLI commands

### GitHub Actions Security
- **NEVER** store credentials in artifacts between jobs
- **Solution**: Consolidate credential operations in single job
- **Rationale**: Artifacts accessible to anyone with repo permissions

### Oracle Cloud Gotchas
- OCID validation is critical: `^ocid1\\.type\\.[a-z0-9-]*\\.[a-z0-9-]*\\..+`
- "Out of host capacity" is expected for free tier (not a failure)
- Flexible shapes need `--shape-config {"ocpus": N, "memoryInGBs": N}`

### Error Classification & Capacity Handling (UPDATED 2025-08-24)
- **CAPACITY/RATE_LIMIT**: Treated as expected success conditions
  - "Out of host capacity" (Oracle free tier limitation)
  - "Too many requests" / HTTP 429 (rate limiting)
  - "Service limit exceeded", "Quota exceeded"
  - "Resource unavailable", "Insufficient capacity"
  - **Result**: Script returns 0 → Workflow succeeds → No false alerts
- **AUTH**: Authentication/authorization errors → Immediate Telegram alert
- **CONFIG**: Invalid parameters/OCIDs → Review needed, Telegram alert
- **NETWORK**: Connectivity/timeout issues → Telegram alert

### Capacity Error Handling Implementation
**Key Files Modified:**
- `scripts/launch-instance.sh` (lines 113-152): Enhanced error handling
- `scripts/utils.sh` (lines 109-120): Expanded error classification patterns  
- `.github/workflows/free-tier-creation.yml`: Added workflow-level safeguards

**Core Logic:**
```bash
# Early rate limit detection to avoid redundant API calls
if echo "$output" | grep -qi "too many requests\|rate limit\|throttle\|429"; then
    return 0  # Treat as success
fi
```

### Performance Optimizations & Debugging Indicators (UPDATED 2025-08-25)

**CRITICAL PERFORMANCE BREAKTHROUGH:**
- **Original execution time**: ~2 minutes (120 seconds)  
- **Optimized execution time**: ~17-18 seconds
- **Performance improvement**: 93% reduction via OCI CLI flag optimization

**Root Cause Analysis:**
- **Problem**: OCI CLI default retry logic with exponential backoff (5 attempts: 2s, 4s, 8s, 16s, 32s delays)
- **Solution**: Added `--no-retry` flag to eliminate automatic retry loops
- **Additional optimization**: Added connection/read timeouts to prevent network hanging

**OCI CLI Optimization Flags (scripts/utils.sh):**
```bash
# Performance flags applied to all OCI CLI commands:
oci_args+=("--no-retry")                    # Disable exponential backoff retry
oci_args+=("--connection-timeout" "5")      # 5s connection timeout (vs 10s default)  
oci_args+=("--read-timeout" "15")           # 15s read timeout (vs 60s default)
```

**Why This Works:**
- Oracle free tier capacity/rate limit errors are **expected** and handled gracefully
- Exponential backoff was counterproductive for expected failures
- Fast failure enables next scheduled attempt in 6 minutes
- Network timeouts prevent workflow hanging on connectivity issues

**Performance Indicators:**
- **<20 seconds runtime**: Optimal performance with capacity/rate limit handling
- **~17-18 seconds**: Normal execution with optimized OCI CLI flags
- **>30 seconds**: Potential network issues or configuration errors
- **>1 minute**: Likely missing performance optimizations or genuine failures

**Debugging Commands:**
- Use `DEBUG=true` and `--field verbose_output=true` for troubleshooting
- Verify optimization flags in logs: `grep "Executing OCI debug command"`
- Expected command: `oci --debug --no-retry --connection-timeout 5 --read-timeout 15`

### Testing Capacity Error Handling
```bash
# Test error classification locally
source scripts/utils.sh && get_error_type "Too many requests for the user"
# Expected output: CAPACITY

# Test workflow with verbose output
gh workflow run free-tier-creation.yml --field verbose_output=true --field send_notifications=false

# Monitor results
gh run watch <run-id>
```

## Advanced Configuration & Implementation Details

### OCI CLI Command Wrapper Architecture (scripts/utils.sh)

The project implements a sophisticated dual-mode OCI CLI wrapper system:

**1. oci_cmd_debug() - For actions requiring detailed logging:**
- Adds `--debug` flag when `DEBUG=true` for troubleshooting
- Includes performance optimization flags: `--no-retry`, `--connection-timeout 5`, `--read-timeout 15`
- Used for instance launch and other critical operations
- Logs full command for debugging: "Executing OCI debug command: oci ..."

**2. oci_cmd_data() - For data extraction without debug pollution:**  
- Optimized for queries that need clean output (JSON parsing, etc.)
- Includes same performance flags but no debug verbosity
- Used for image lookup, instance listing, and data retrieval operations

**3. oci_cmd() - Intelligent router:**
- Automatically selects appropriate mode based on command arguments
- Uses `oci_cmd_data()` for commands with `--query` or `--raw-output`
- Uses `oci_cmd_debug()` for action commands (launch, create, etc.)

### Image Caching Strategy (scripts/launch-instance.sh)

**Smart Image Resolution Logic:**
```bash
# Priority order for image selection:
1. OCI_IMAGE_ID (explicit override) 
2. Cached image IDs (OCI_CACHED_OL9_ARM_IMAGE, OCI_CACHED_OL9_AMD_IMAGE)
3. API lookup with filters (fallback, slower)
```

**Cached Image Patterns:**
- `Oracle Linux_9_VM.Standard.A1.Flex` → ARM-based free tier shape
- `Oracle Linux_9_VM.Standard.E2.1.Micro` → AMD-based free tier shape
- Cache keys: `"${OPERATING_SYSTEM}_${OS_VERSION}_${OCI_SHAPE}"`

### Workflow Environment Variables & Logic

**Critical Environment Variables:**
- `DEBUG`: Controls verbose OCI CLI output (`--debug` flag)
- `ENABLE_NOTIFICATIONS`: Controls Telegram notification sending
- `CHECK_EXISTING_INSTANCE`: Smart instance checking logic
  - Manual runs (`workflow_dispatch`): Respects user input
  - Scheduled runs: Always `false` (direct launch for performance)
- `OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING`: Prevents GitHub Actions noise

**Workflow Input Parameters:**
- `verbose_output` (boolean): Enables debug mode for troubleshooting
- `send_notifications` (boolean): Controls Telegram alerts
- `check_existing_instance` (boolean): Enable/disable duplicate checking

### Error Detection Patterns (scripts/utils.sh get_error_type())

**Comprehensive Error Classification Regex Patterns:**

**CAPACITY Errors:**
```bash
"capacity|host capacity|out of capacity|service limit|quota exceeded|resource unavailable|insufficient capacity"
```

**RATE_LIMIT Errors (treated as CAPACITY):**
```bash
"too.*many.*requests|rate.*limit|throttle|429|TooManyRequests|\"code\".*\"TooManyRequests\"|\"status\".*429"
```

**DUPLICATE Errors (treated as success):**
```bash
"display name already exists|instance.*already exists|duplicate.*name"
```

**AUTH/CONFIG/NETWORK Errors:** Standard patterns for genuine failures

### Performance Monitoring & Timing Infrastructure

**Built-in Timer System (scripts/utils.sh):**
- `start_timer()`: Records start time for performance phase
- `log_elapsed()`: Calculates and logs elapsed time for analysis
- Uses `date +%s.%N` for nanosecond precision timing
- Automatic cleanup of timer variables after logging

**Key Performance Phases Monitored:**
- `total_execution`: End-to-end workflow timing
- `oci_cli_check`: CLI availability verification  
- `compartment_setup`: Compartment ID determination
- `existing_instance_check`: Instance existence verification (when enabled)
- `image_lookup`: Image ID resolution (cached vs API)
- `instance_launch`: Actual OCI API call execution

### GitHub Actions Security Patterns

**Single-Job Security Model:**
- All credential handling in `create-instance` job only
- No credential passing through artifacts (security risk)
- Secrets only available in environment variables during execution
- `notify-on-failure` job runs independently without credentials

**Credential Environment Variables:**
All OCI credentials are passed as environment variables, never as parameters:
```yaml
env:
  OCI_USER_OCID: ${{ secrets.OCI_USER_OCID }}
  OCI_PRIVATE_KEY: ${{ secrets.OCI_PRIVATE_KEY }}
  # ... other secrets
```

### Troubleshooting Decision Tree

**Execution Time Analysis:**
- **<20 seconds**: Normal optimized performance ✅
- **20-30 seconds**: Acceptable, possible minor network delays
- **30-60 seconds**: Investigate - missing optimizations or config issues ⚠️  
- **1-2 minutes**: Critical - likely missing `--no-retry` flag ❌
- **>2 minutes**: Severe - multiple optimization failures ❌

**Debug Flag Verification:**
```bash
# Check if optimization flags are present in logs:
grep "Executing OCI debug command" logs.txt
# Should show: oci --debug --no-retry --connection-timeout 5 --read-timeout 15
```

**Common Issues & Solutions:**
1. **Missing performance flags**: Verify `scripts/utils.sh` has optimization flags
2. **Wrong error classification**: Check `get_error_type()` regex patterns  
3. **Credential issues**: Verify all GitHub secrets are configured
4. **Network timeouts**: Check connection/read timeout values (5s/15s)

### Oracle Cloud Infrastructure Specifics

**Free Tier Behavior Patterns:**
- Capacity errors are **normal** - Oracle has limited free tier resources
- ARM instances (A1.Flex) more commonly available than AMD (E2.1.Micro)
- Rate limiting (HTTP 429) indicates high demand, not system issues
- "Out of host capacity" is expected response during high usage periods

**OCID Format Validation:**
- Pattern: `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- All OCI resources have globally unique OCIDs
- Critical for API calls - invalid OCIDs cause immediate failures

**Shape Configuration Requirements:**
- Flexible shapes (`*.Flex`) require explicit `--shape-config` parameter
- Format: `{"ocpus": N, "memoryInGBs": N}`
- Fixed shapes (like `*.Micro`) do not need shape configuration