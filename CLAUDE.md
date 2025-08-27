# CLAUDE.md

OCI free-tier automation: parallel A1.Flex (ARM) + E2.1.Micro (AMD) provisioning via GitHub Actions.

## Architecture

```text
.github/workflows/free-tier-creation.yml  # Single-job parallel execution
scripts/
├── launch-parallel.sh      # Orchestrates both shapes with env injection
├── launch-instance.sh      # Shape-agnostic creation + transient retry
├── utils.sh               # OCI CLI wrapper + error classification
├── circuit-breaker.sh     # AD failure tracking (3 failures = skip)
├── setup-oci.sh          # CLI + proxy setup
├── validate-config.sh    # Configuration validation
└── notify.sh             # Telegram notifications
tests/
├── test_proxy.sh         # Proxy validation (15 tests)
├── test_integration.sh   # Integration tests (9 tests)
├── test_circuit_breaker.sh # Circuit breaker (9 tests)
└── run_new_tests.sh      # Test runner
```

## Critical Patterns

### Performance Optimization (93% improvement)
```bash
# NEVER remove these flags in utils.sh:
oci_args+=("--no-retry")                    # Eliminates exponential backoff
oci_args+=("--connection-timeout" "5")      # 5s vs 10s default
oci_args+=("--read-timeout" "15")           # 15s vs 60s default
```

### Error Classification (scripts/utils.sh)
```bash
CAPACITY: "capacity|quota|limit|429"        → Schedule retry (treat as success)
DUPLICATE: "already exists"                 → Success
TRANSIENT: "internal|network|timeout"       → Retry 3x same AD, then next AD
AUTH/CONFIG: "authentication|invalid.*ocid" → Alert user immediately
```

### Parallel Execution Pattern (launch-parallel.sh)
```bash
# Environment variable injection per shape:
(export OCI_SHAPE="VM.Standard.A1.Flex" OCI_OCPUS="4" OCI_MEMORY_IN_GBS="24"; ./launch-instance.sh) &
(export OCI_SHAPE="VM.Standard.E2.1.Micro" OCI_OCPUS="" OCI_MEMORY_IN_GBS=""; ./launch-instance.sh) &
wait  # 55s timeout protection
```

### Shape Configurations
```bash
# A1.Flex (ARM) - 4 OCPUs, 24GB, instance name: a1-flex-sg
# E2.1.Micro (AMD) - 1 OCPU, 1GB, instance name: e2-micro-sg
```

## Development Commands

```bash
# Configuration validation
./scripts/validate-config.sh

# Local testing (requires environment variables)
./scripts/setup-oci.sh           # OCI CLI + proxy setup
./scripts/launch-parallel.sh     # Both shapes in parallel
./scripts/launch-instance.sh     # Single shape (with env vars)

# Test suites
./tests/test_proxy.sh             # Proxy validation (15 tests)
./tests/test_integration.sh       # Integration tests (9 tests)
./tests/test_circuit_breaker.sh   # Circuit breaker functionality (9 tests)
./tests/run_new_tests.sh          # Test runner for enhancements

# Syntax validation
bash -n scripts/*.sh

# Debug mode
DEBUG=true ./scripts/launch-instance.sh
```

## Environment Variables

```bash
# Multi-AD Support (comma-separated)
OCI_AD="fgaj:AP-SINGAPORE-1-AD-1,fgaj:AP-SINGAPORE-1-AD-2,fgaj:AP-SINGAPORE-1-AD-3"

# Performance & Reliability
BOOT_VOLUME_SIZE="50"                    # GB, minimum enforced
RECOVERY_ACTION="RESTORE_INSTANCE"       # Auto-restart on failures
RETRY_WAIT_TIME="30"                     # Seconds between AD attempts
TRANSIENT_ERROR_MAX_RETRIES="3"         # Retry count per AD
TRANSIENT_ERROR_RETRY_DELAY="15"        # Seconds between retries

# Debugging
DEBUG="true"                             # Enable verbose OCI CLI output
LOG_FORMAT="text"                        # or "json" for structured logging
```

## Workflow Testing

```bash
# Manual run with debug
gh workflow run free-tier-creation.yml --field verbose_output=true --field send_notifications=false

# Monitor execution
gh run watch <run-id>

# Expected timing: ~20-25 seconds total, ~14 seconds parallel phase
```

## Error Patterns

### Expected Behaviors
- **Capacity limitations are normal** - Oracle Cloud has dynamic resource availability
- **Rate limiting (HTTP 429)** - High demand, standard cloud provider behavior  
- **"Out of host capacity"** - Common during peak usage periods
- **ARM (A1.Flex) typically more available** than AMD (E2.1.Micro)

### OCID Validation
```bash
# Pattern: ^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+
# All OCI resources have globally unique OCIDs
```

### Transient Error Retry Pattern
```bash
# For INTERNAL_ERROR and NETWORK errors:
# 1. Retry same AD up to 3 times (15 second delays)
# 2. If still failing, try next availability domain
# 3. If all ADs exhausted, treat as capacity issue
```

## Gotchas

- **Capacity errors are EXPECTED** (treat as success - retry on schedule)
- **Single job strategy** (avoid matrix = 2x GitHub Actions cost)
- **55-second timeout protection** prevents 2-minute billing
- **Proxy inheritance**: Environment variables auto-propagate to parallel processes
- **Shape requirements**: Flexible shapes need `--shape-config` parameter
- **Never remove** OCI CLI optimization flags - they provide 93% performance improvement

## Oracle Cloud Specifics

- **Flexible shapes need --shape-config parameter**: `{"ocpus": 4, "memoryInGBs": 24}`
- **Fixed shapes (*.Micro) do not need shape configuration**
- **OCID validation**: `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- **Proxy formats**: `username:password@proxy.example.com:3128` (URL encoding supported)

## Performance Indicators

- **<20 seconds**: Optimal performance ✅
- **20-30 seconds**: Acceptable with minor delays
- **30-60 seconds**: Investigate - config/network issues ⚠️
- **>1 minute**: Critical - missing optimizations ❌