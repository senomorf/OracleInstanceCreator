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
- Never store credentials in artifacts or other places with broader access scope