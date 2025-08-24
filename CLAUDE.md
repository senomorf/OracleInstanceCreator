# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Oracle Cloud Infrastructure (OCI) automation project that uses GitHub Actions to automatically attempt creating free tier instances. The project is designed to periodically retry instance creation when Oracle's free tier capacity is available.

## Architecture

The project has been refactored into a modular architecture with the following components:

### File Structure
```
├── .github/workflows/free-tier-creation.yml  # GitHub Actions workflow (refactored)
├── scripts/
│   ├── setup-oci.sh                          # OCI CLI configuration
│   ├── setup-ssh.sh                          # SSH key setup  
│   ├── validate-config.sh                    # Configuration validation
│   ├── launch-instance.sh                    # Instance creation logic
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

The GitHub Actions workflow consists of two secure jobs:

1. **create-instance**: Validates configuration, sets up environment, and creates OCI instance (consolidated for security)
2. **notify-on-failure**: Sends failure notifications if the main job fails

**Security Enhancement**: All credential operations occur within a single job to prevent exposure through artifacts.

## Key Configuration

The workflow is configured via environment variables in the GitHub Actions file:

- **OCI_AD**: Availability Domain (e.g., "fgaj:AP-SINGAPORE-1-AD-1")
- **OCI_SHAPE**: Instance shape (e.g., "VM.Standard.A1.Flex")
- **OCI_OCPUS**: Number of OCPUs for flexible shapes
- **OCI_MEMORY_IN_GBS**: Memory in GB for flexible shapes
- **INSTANCE_DISPLAY_NAME**: Display name for the instance
- **OPERATING_SYSTEM**: OS name (e.g., "Oracle Linux")
- **OS_VERSION**: OS version (e.g., "9")

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
- **Scheduled**: Currently commented out, but supports cron scheduling

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
./scripts/launch-instance.sh     # Launch instance
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

- **Refactored Architecture**: The project has been transformed from a monolithic workflow into a modular system with separate scripts for different functions
- **Enhanced Testability**: Individual scripts can now be tested locally without GitHub Actions
- **Improved Error Handling**: Comprehensive error classification with intelligent retry logic and notifications  
- **Configuration Management**: Structured configuration files support multiple deployment scenarios
- **Backward Compatibility**: All existing GitHub secrets and functionality are preserved
- **Better Maintainability**: Clear separation of concerns makes the system easier to understand and modify
- **Comprehensive Documentation**: Detailed documentation available in `docs/configuration.md`

## Critical Technical Patterns (Lessons Learned)

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

### Debugging Indicators & Performance Optimizations
- **<30 seconds runtime**: Configuration/parsing errors (genuine failures)
- **~2 minutes runtime**: Successful API calls reaching Oracle (capacity/rate limit expected)
- **Single API Call**: Direct `oci` CLI usage prevents redundant requests on rate limiting
- **Workflow Success Pattern**: Capacity Error → Exit 0 → Green Status → No Alert
- Use `DEBUG=true` and `--field verbose_output=true` for troubleshooting

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