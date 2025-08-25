# CLAUDE.md

Oracle Cloud Infrastructure (OCI) automation for **parallel free tier instance creation**. Simultaneously attempts both ARM (A1.Flex) and AMD (E2.1.Micro) shapes using GitHub Actions with billing optimization.

## Architecture

**Core Components:**
```
├── .github/workflows/free-tier-creation.yml  # Single-job parallel execution
├── scripts/
│   ├── launch-parallel.sh                    # Orchestrates both shapes
│   ├── launch-instance.sh                    # Shape-agnostic creation logic
│   ├── utils.sh                              # Common functions + proxy support
│   ├── setup-oci.sh                          # OCI CLI + proxy configuration
│   ├── validate-config.sh                    # Configuration validation
│   └── notify.sh                             # Telegram notifications
└── tests/test_proxy.sh                       # Proxy validation (15 tests)
```

**Parallel Execution Flow:**
1. `launch-parallel.sh` launches both shapes as background processes (`&`)
2. Each calls `launch-instance.sh` with shape-specific environment variables
3. Multi-AD cycling per shape with independent error handling
4. 55-second timeout protection prevents 2-minute GitHub Actions billing

## Configuration

### Required GitHub Secrets
```yaml
# OCI Authentication
OCI_USER_OCID: Oracle user OCID
OCI_KEY_FINGERPRINT: API key fingerprint
OCI_TENANCY_OCID: Tenancy OCID
OCI_REGION: OCI region
OCI_PRIVATE_KEY: Private API key content

# Instance Configuration
OCI_COMPARTMENT_ID: Compartment OCID (optional, uses tenancy)
OCI_SUBNET_ID: Subnet OCID
OCI_IMAGE_ID: Image OCID (optional, auto-detected)
INSTANCE_SSH_PUBLIC_KEY: SSH public key

# Notifications
TELEGRAM_TOKEN: Telegram bot token
TELEGRAM_USER_ID: Telegram user ID

# Proxy (Optional)
OCI_PROXY_URL: username:password@proxy.example.com:3128
```

### Shape Configurations
```bash
# A1.Flex (ARM) - 4 OCPUs, 24GB, instance name: a1-flex-sg
# E2.1.Micro (AMD) - 1 OCPU, 1GB, instance name: e2-micro-sg
```

### Environment Variables
```bash
# Multi-AD Support (comma-separated)
OCI_AD: "fgaj:AP-SINGAPORE-1-AD-1,fgaj:AP-SINGAPORE-1-AD-2,fgaj:AP-SINGAPORE-1-AD-3"

# Performance & Reliability
BOOT_VOLUME_SIZE: "50"                    # GB, minimum enforced
RECOVERY_ACTION: "RESTORE_INSTANCE"       # Auto-restart on failures
RETRY_WAIT_TIME: "30"                     # Seconds between AD attempts
INSTANCE_VERIFY_MAX_CHECKS: "5"          # Verification attempts
INSTANCE_VERIFY_DELAY: "30"              # Seconds between verifications

# Debugging
DEBUG: "true"                             # Enable verbose OCI CLI output
LOG_FORMAT: "text"                        # or "json" for structured logging
```

## Critical Technical Patterns

### Performance Optimization (93% improvement)
```bash
# OCI CLI flags in utils.sh - NEVER remove these:
oci_args+=("--no-retry")                    # Eliminates exponential backoff
oci_args+=("--connection-timeout" "5")      # 5s vs 10s default
oci_args+=("--read-timeout" "15")           # 15s vs 60s default
```

### Error Classification (scripts/utils.sh)
```bash
# CAPACITY (treated as success - retry on schedule)
"capacity|host capacity|out of capacity|service limit|quota exceeded|too.*many.*requests|429"

# DUPLICATE (treated as success)  
"display name already exists|instance.*already exists"

# AUTH/CONFIG (immediate Telegram alert)
"authentication|authorization|invalid.*ocid|not found"
```

### Parallel Execution Pattern
```bash
# Environment variable injection per shape:
(export OCI_SHAPE="VM.Standard.A1.Flex"; export OCI_OCPUS="4"; ./launch-instance.sh) &
(export OCI_SHAPE="VM.Standard.E2.1.Micro"; export OCI_OCPUS=""; ./launch-instance.sh) &
wait
```

### GitHub Actions Security
- **Single job strategy**: All credentials in one job (no artifacts)
- **Timeout protection**: 55-second limit prevents 2-minute billing
- **Proxy inheritance**: Environment variables auto-propagate to parallel processes

## Development Commands

### Local Testing
```bash
# Syntax validation
bash -n scripts/*.sh

# Configuration validation
./scripts/validate-config.sh

# Proxy testing (15 test cases)
./tests/test_proxy.sh

# Individual components (requires environment variables)
./scripts/setup-oci.sh           # OCI CLI + proxy setup
./scripts/launch-parallel.sh     # Both shapes in parallel
./scripts/launch-instance.sh     # Single shape (with env vars)
```

### Workflow Testing
```bash
# Manual run with debug
gh workflow run free-tier-creation.yml --field verbose_output=true --field send_notifications=false

# Monitor execution
gh run watch <run-id>

# Expected timing: ~20-25 seconds total, ~14 seconds parallel phase
```

### Performance Debugging
```bash
# Verify optimization flags in logs
grep "Executing OCI debug command" logs.txt
# Should show: oci --debug --no-retry --connection-timeout 5 --read-timeout 15

# Test error classification
source scripts/utils.sh && get_error_type "Too many requests"
# Expected: CAPACITY
```

## Oracle Cloud Specifics

### Expected Behaviors
- **Capacity errors are normal** - Oracle has limited free tier resources
- **Rate limiting (HTTP 429)** - High demand, not system issues  
- **"Out of host capacity"** - Expected during peak usage
- **ARM (A1.Flex) typically more available** than AMD (E2.1.Micro)

### OCID Validation
```bash
# Pattern: ^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+
# All OCI resources have globally unique OCIDs
```

### Shape Requirements
```bash
# Flexible shapes need --shape-config parameter
--shape-config '{"ocpus": 4, "memoryInGBs": 24}'

# Fixed shapes (*.Micro) do not need shape configuration
```

## Proxy Support

### Configuration Formats
```bash
# IPv4: username:password@proxy.example.com:3128
# IPv6: username:password@[::1]:3128  
# URL encoding supported for special characters in passwords
# Example: myuser:my%40pass@proxy.com:3128 (for password my@pass)
```

### Troubleshooting
```bash
# Test proxy configuration
export OCI_PROXY_URL="user:pass@proxy.example.com:3128"
./scripts/validate-config.sh

# Debug proxy setup
DEBUG=true ./scripts/setup-oci.sh

# Verify environment variables
echo $HTTP_PROXY $HTTPS_PROXY
```

## Performance Indicators

### Execution Timing
- **<20 seconds**: Optimal performance ✅
- **20-30 seconds**: Acceptable with minor delays
- **30-60 seconds**: Investigate - config/network issues ⚠️
- **>1 minute**: Critical - missing optimizations ❌

### Success Scenarios
- **Both instances created**: Maximum free tier achieved
- **One instance created**: Partial success, retry other shape next run  
- **Zero instances created**: Capacity unavailable, retry on schedule

## Production Validation (2025-08-25)

**✅ VALIDATED**: Run #17219156038 - Perfect implementation validation
- **Total Execution**: 32 seconds (1-minute billing confirmed)
- **Parallel Phase**: 14.04 seconds for both shapes
- **Success Rate**: 100% - Both A1.Flex and E2.1.Micro created
- **Proxy Integration**: Seamless inheritance by parallel processes
- **Performance**: 93% improvement maintained (14s vs previous 2 minutes)
- **Architecture**: Clean separation of concerns confirmed

## Important Notes

- **Never remove** OCI CLI optimization flags - they provide 93% performance improvement
- **Capacity errors are expected** - treat as success, retry on schedule  
- **Single job billing** - avoid matrix strategy (2x cost)
- **Proxy is optional** - if not configured, connects directly to Oracle Cloud
- **Multi-AD cycling** - dramatically increases success rates
- **Security**: All credentials masked in logs, no exposure risk