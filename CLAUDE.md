# CLAUDE.md

OCI free-tier automation: parallel A1.Flex (ARM) + E2.1.Micro (AMD) provisioning via GitHub Actions.

## Architecture

**Core Scripts:**
- `scripts/launch-parallel.sh` - Orchestrates both shapes with env injection
- `scripts/launch-instance.sh` - Shape-agnostic creation + transient retry
- `scripts/utils.sh` - OCI CLI wrapper + error classification
- `scripts/circuit-breaker.sh` - AD failure tracking (3 failures = skip)
- `scripts/setup-oci.sh` - CLI + proxy setup
- `scripts/adaptive-scheduler.sh` - Success pattern optimization
- `scripts/preflight-check.sh` - Production validation
- `scripts/constants.sh` - Centralized configuration constants
- `scripts/metrics.sh` - Performance tracking system

**Tests:** 14 test scripts with 31+ automated tests in `tests/` directory

## Critical Patterns

### Performance Optimization (NEVER remove in utils.sh)
```bash
oci_args+=("--no-retry")                    # Eliminates exponential backoff
oci_args+=("--connection-timeout" "5")      # 5s vs 10s default
oci_args+=("--read-timeout" "15")           # 15s vs 60s default
```

### Error Classification (scripts/utils.sh)
```bash
CAPACITY: "capacity|quota|limit|429"        → Retry on schedule (success)
DUPLICATE: "already exists"                 → Success
TRANSIENT: "internal|network|timeout"       → Retry 3x same AD, then cycle
AUTH/CONFIG: "authentication|invalid.*ocid" → Immediate alert
```

### Parallel Execution (launch-parallel.sh)
```bash
(export OCI_SHAPE="VM.Standard.A1.Flex" OCI_OCPUS="4" OCI_MEMORY_IN_GBS="24"; ./launch-instance.sh) &
(export OCI_SHAPE="VM.Standard.E2.1.Micro" OCI_OCPUS="" OCI_MEMORY_IN_GBS=""; ./launch-instance.sh) &
wait  # 55s timeout protection
```

## Environment Variables

**Multi-AD Support:**
`OCI_AD="fgaj:AP-SINGAPORE-1-AD-1,fgaj:AP-SINGAPORE-1-AD-2,fgaj:AP-SINGAPORE-1-AD-3"`

**Critical Settings:**
- `BOOT_VOLUME_SIZE="50"` - GB minimum
- `RETRY_WAIT_TIME="30"` - Seconds between AD attempts
- `TRANSIENT_ERROR_MAX_RETRIES="3"` - Same-AD retry count
- `DEBUG="true"` - Enable verbose output

## Shape Configurations

| Shape | OCPUs | Memory | Instance Name |
|-------|--------|--------|---------------|
| VM.Standard.A1.Flex | 4 | 24GB | a1-flex-sg |
| VM.Standard.E2.1.Micro | 1 | 1GB | e2-micro-sg |

## Development Commands

```bash
# Testing and validation
make lint                          # Run all linters
./scripts/preflight-check.sh       # Production validation
./tests/run_new_tests.sh           # All test suites

# Local execution
DEBUG=true ./scripts/launch-parallel.sh
./scripts/adaptive-scheduler.sh    # Schedule optimization

# GitHub workflow
gh workflow run infrastructure-deployment.yml --field verbose_output=true
```

## Key Constraints

- **Capacity errors are EXPECTED** - treat as success, retry on schedule
- **Single job strategy** - avoid matrix (2x cost)
- **55s timeout** - prevents 2-minute GitHub billing
- **Flexible shapes need** `--shape-config` parameter
- **Fixed shapes** (*.Micro) do not need shape configuration

## Advanced Features

### Circuit Breaker (scripts/circuit-breaker.sh)
- Skips ADs after 3 consecutive failures
- 24-hour auto-reset
- 30% reduction in failed attempts

### Exponential Backoff
- Sequence: 5s → 10s → 20s → 40s (max)
- Applied to INTERNAL_ERROR and NETWORK types

### Performance Metrics (scripts/metrics.sh)
- Shape-specific execution timing
- Parallel efficiency tracking
- Resource usage monitoring

## Configuration Files

**Project Structure:**
- `config/defaults.yml` - Default configurations
- `config/instance-profiles.yml` - Shape definitions
- `config/regions.yml` - Regional settings
- `docs/dashboard/` - Web dashboard with GitHub integration

## Linting Standards

**Required:** ESLint (JS), djlint (HTML), shellcheck (shell), yamllint (YAML), actionlint (workflows), markdownlint (docs)

**Commands:**
```bash
make lint                          # All linters
make lint-fix                      # Auto-fix where possible
shellcheck scripts/*.sh tests/*.sh # Shell validation
```

## Oracle Cloud Specifics

- **OCID Pattern:** `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- **Proxy Format:** `username:password@proxy.example.com:3128`
- **"Out of host capacity"** is expected during peak usage
- **ARM (A1.Flex) typically more available** than AMD (E2.1.Micro)

## Dashboard Integration

**Files:** `docs/dashboard/index.html`, `docs/dashboard/js/dashboard.js`
**Features:** GitHub API integration, rate limiting, XSS protection via safe DOM manipulation

## Troubleshooting Quick Reference

**Rate limiting:** Check GitHub token, wait for reset
**XSS errors:** Safe DOM manipulation implemented (2025-08-27)
**Linting failures:** Run `make lint-fix`, check specific linters
**Capacity issues:** Expected behavior - retry on schedule
**Performance < 20s:** Optimal, **> 60s:** Check optimization flags

## Important Notes

- Never remove OCI CLI optimization flags
- Capacity errors = success (Oracle's dynamic availability)
- Proxy optional (direct connection fallback)
- All credentials masked in logs
- Multi-AD cycling increases success rates significantly

**Git Rules:** Lookup actual GitHub user/repo, don't assume from folder names. Never disable super-linter or other linter jobs.