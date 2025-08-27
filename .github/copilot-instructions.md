# GitHub Copilot Instructions - OCI Free Tier Automation

## Project Overview
Oracle Cloud Infrastructure (OCI) free-tier automation with parallel A1.Flex (ARM) + E2.1.Micro (AMD) provisioning via GitHub Actions. Achieves ~20s execution with 93% performance optimization through CLI tuning.

## Critical Performance Patterns
**NEVER modify these optimizations** - they provide 93% performance improvement:
```bash
# Required OCI CLI flags (scripts/utils.sh):
oci_args+=("--no-retry")                    # Eliminates exponential backoff
oci_args+=("--connection-timeout" "5")      # Fast fail vs 10s default
oci_args+=("--read-timeout" "15")           # Quick timeout vs 60s default
```

## Architecture Essentials
```
scripts/
├── launch-parallel.sh      # Orchestrates both shapes with env injection
├── launch-instance.sh      # Shape-agnostic creation + transient retry
├── utils.sh               # OCI CLI wrapper + error classification
├── circuit-breaker.sh     # AD failure tracking (3 failures = skip)
└── setup-oci.sh          # CLI + proxy setup
```

## Error Classification (Critical for Review)
```bash
CAPACITY: "capacity|quota|limit|429"        → SUCCESS (schedule retry)
DUPLICATE: "already exists"                 → SUCCESS  
TRANSIENT: "internal|network|timeout"       → Retry 3x same AD, then next
AUTH/CONFIG: "authentication|invalid.*ocid" → FAILURE (alert user)
```

## Code Review Priorities

### 1. Security (Critical)
- **No credential exposure**: OCIDs, keys, tokens must use GitHub Secrets only
- **Log redaction**: Sensitive data shows as `[REDACTED]` or `ocid1234...5678`
- **File permissions**: Temporary files use 600/700 permissions
- **Input validation**: All user inputs sanitized, OCID format validated

### 2. Performance (Critical)
- **Execution target**: <25 seconds total, ~20s parallel phase
- **GitHub Actions billing**: Single job execution (avoid matrix strategy)
- **Timeout protection**: 55s hard limit prevents 2-minute billing
- **CLI optimization flags**: Must be present in all OCI commands

### 3. Reliability Patterns
- **Parallel execution**: Environment variable injection for each shape
- **Circuit breaker**: Skip ADs after 3 consecutive failures
- **Transient retry**: 3 attempts per AD with exponential backoff
- **Instance verification**: Re-check creation after LimitExceeded errors

### 4. Testing & Quality
- **Test coverage**: 31 automated tests (15 proxy + 9 integration + 9 circuit breaker)
- **Error handling**: Proper classification and retry logic
- **Bounds validation**: Timeouts 1-300s, retries 1-10, delays 1-60s
- **Process management**: Existence checks before termination

## OCI-Specific Requirements

### Shape Configurations
```bash
# A1.Flex (ARM): 4 OCPUs, 24GB, flexible shape needs --shape-config
# E2.1.Micro (AMD): 1 OCPU, 1GB, fixed shape (no config needed)
```

### OCID Validation
- Pattern: `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- All Oracle resources have globally unique OCIDs
- Must validate format before API calls

### Multi-AD Support
- Format: `"AD-1,AD-2,AD-3"` (comma-separated)
- Each shape cycles independently
- Circuit breaker tracks failures per AD

## GitHub Actions Cost Management
- **Current usage**: ~7,200 minutes/month (scheduled runs)
- **Free tier limit**: 2,000 minutes/month
- **Optimization**: Single job strategy vs matrix (2x cost)
- **Billing**: Each run rounds up to 1 minute minimum

## Development Commands Reference
```bash
# Local testing
./scripts/validate-config.sh      # Configuration validation
./scripts/launch-parallel.sh      # Test parallel execution
DEBUG=true ./scripts/launch-instance.sh  # Debug single shape

# Test suites  
./tests/test_proxy.sh             # 15 proxy tests
./tests/test_integration.sh       # 9 integration tests
./tests/test_circuit_breaker.sh   # 9 circuit breaker tests

# Syntax validation
bash -n scripts/*.sh

# Workflow testing
gh workflow run free-tier-creation.yml --field verbose_output=true
```

## Common Review Issues

### High Priority (Block PR)
1. **Credential exposure**: Hardcoded OCIDs, keys, tokens
2. **Performance regression**: Missing CLI optimization flags
3. **Security flaws**: Unvalidated inputs, command injection risks
4. **Logic errors**: Improper error classification, retry logic bugs
5. **Cost impact**: Matrix strategy or long-running workflows

### Medium Priority (Request fixes)
1. **Missing tests**: New functionality without test coverage
2. **Error handling**: Improper classification of OCI errors
3. **Resource cleanup**: Process management issues
4. **Documentation**: Missing technical patterns or security notes

### Low Priority (Suggestions)
1. **Code style**: Formatting inconsistencies
2. **Minor optimizations**: Non-critical performance improvements
3. **Documentation**: Minor clarity improvements

## Success Criteria
- **Performance**: Maintain ~20-25s execution time
- **Security**: Zero credential exposures, proper redaction
- **Reliability**: Proper error handling and retry logic
- **Cost**: Stay within GitHub Actions free tier
- **Quality**: Comprehensive test coverage with 100% pass rate

## Expected Behaviors (Not Errors)
- **Capacity errors are normal**: Oracle has limited free resources
- **"Out of host capacity"**: Common during peak usage periods
- **Rate limiting (429)**: Standard cloud provider behavior
- **ARM typically more available**: Than AMD instances

## Gotchas for Reviewers
- **Capacity errors = SUCCESS**: Should be treated as success, not failure
- **Single job strategy**: Avoid matrix builds (doubles cost)
- **55-second timeout**: Protects against 2-minute billing
- **Proxy inheritance**: Environment variables auto-propagate to parallel processes
- **Never remove optimization flags**: They provide 93% performance improvement