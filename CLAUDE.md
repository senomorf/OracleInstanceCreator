# CLAUDE.md

Oracle Cloud Infrastructure (OCI) automation project using GitHub Actions for free tier instance creation.

## Architecture

```
├── .github/workflows/free-tier-creation.yml  # Main workflow
├── scripts/
│   ├── setup-oci.sh                          # OCI CLI setup
│   ├── setup-ssh.sh                          # SSH key setup  
│   ├── validate-config.sh                    # Config validation
│   ├── launch-instance.sh                    # Instance creation
│   ├── notify.sh                             # Telegram alerts
│   └── utils.sh                              # Common utilities
├── tests/                                     # Test framework
└── config/                                    # Configuration files
```

## Key Configuration

### Required GitHub Secrets
- **OCI**: `OCI_USER_OCID`, `OCI_KEY_FINGERPRINT`, `OCI_TENANCY_OCID`, `OCI_REGION`, `OCI_PRIVATE_KEY`
- **Network**: `OCI_SUBNET_ID` 
- **Instance**: `INSTANCE_SSH_PUBLIC_KEY`
- **Notifications**: `TELEGRAM_TOKEN`, `TELEGRAM_USER_ID`

### Optional Secrets
- `OCI_COMPARTMENT_ID` (uses tenancy if unset)
- `OCI_IMAGE_ID` (auto-detected if unset)
- `OCI_PROXY_URL` (proxy support: `user:pass@host:port`, IPv6: `user:pass@[::1]:port`)

### Environment Variables (Workflow)
```yaml
OCI_AD: "fgaj:AP-SINGAPORE-1-AD-1"              # Single or comma-separated ADs
OCI_SHAPE: "VM.Standard.A1.Flex"                 # Instance shape
OCI_OCPUS: "4"                                   # CPUs for flex shapes
OCI_MEMORY_IN_GBS: "24"                         # Memory for flex shapes
TRANSIENT_ERROR_MAX_RETRIES: "3"                # Retry count per AD
TRANSIENT_ERROR_RETRY_DELAY: "15"               # Seconds between retries
```

## Critical Technical Patterns

### Error Classification
- **CAPACITY/RATE_LIMIT**: Expected Oracle limitations → return 0 (success)
- **INTERNAL_ERROR/NETWORK**: Transient → retry same AD 3x, then next AD
- **LIMIT_EXCEEDED**: Check if instance created despite error
- **AUTH/CONFIG**: Genuine failures → return 1, send alerts

### Performance Optimizations
```bash
# Applied to all OCI CLI commands:
--no-retry --connection-timeout 5 --read-timeout 15
```
**Result**: 93% performance improvement (2min → 17-18sec)

### Multi-AD Cycling
```bash
OCI_AD: "AD-1,AD-2,AD-3"  # Tries each AD on failure
```

### Security Patterns
- All credentials in single GitHub Actions job (no artifacts)
- Parameter redaction in logs: OCIDs show `ocid1234...5678`
- SSH keys/private keys replaced with `[REDACTED]`

## Development Commands

### Testing
```bash
# Syntax check
bash -n scripts/*.sh

# Run tests
./tests/test_utils.sh

# Local testing (requires env vars)
./scripts/validate-config.sh
./scripts/launch-instance.sh
```

### Debugging
```bash
# Enable debug mode
DEBUG=true ./scripts/launch-instance.sh

# Manual workflow run
gh workflow run free-tier-creation.yml --field verbose_output=true

# Check optimization flags in logs
grep "Executing OCI debug command" logs.txt
```

## Anti-Patterns (NEVER DO)

### Command Substitution + Logging
```bash
# ❌ WRONG - injects log text into command
result=$(some_function_that_logs)

# ✅ CORRECT - log to stderr
echo "message" >&2
```

### GitHub Actions Security
- ❌ Never store credentials in artifacts between jobs
- ❌ Never use `git add -i` or interactive commands
- ✅ Consolidate credential operations in single job

### Oracle Cloud Gotchas
- "Out of host capacity" is **expected** for free tier (not failure)
- OCID validation: `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- Flexible shapes need `--shape-config {"ocpus": N, "memoryInGBs": N}`

## Performance Indicators
- **17-18 seconds**: Optimal execution time
- **>30 seconds**: Investigation needed
- **>1 minute**: Missing `--no-retry` flag or other optimizations

## Current Status
- **Transient Error Retry**: Added same-AD retry before cycling
- **Compartment Fallback**: Optional compartment ID with tenancy fallback
- **Test Coverage**: 31 automated tests, 100% pass rate
- **Performance**: Maintained 17-18s execution time
- **Security**: All credentials properly redacted in logs