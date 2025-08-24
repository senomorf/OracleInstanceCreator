# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Oracle Cloud Infrastructure (OCI) automation project that uses GitHub Actions to automatically attempt creating free tier instances. The project is designed to periodically retry instance creation when Oracle's free tier capacity is available.

## Architecture

The project consists of a single GitHub Actions workflow (`free-tier-creation.yml`) that:

1. **Sets up the environment**: Installs OCI CLI via pip and configures authentication
2. **Configures OCI authentication**: Uses GitHub secrets to set up OCI configuration files
3. **Sets up SSH keys**: Prepares SSH public keys for instance access
4. **Attempts instance creation**: Launches OCI free tier instances with specified configuration
5. **Handles capacity issues**: Gracefully handles "out of capacity" responses and retries
6. **Provides notifications**: Sends Telegram notifications on success or unexpected errors

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

Since this is a GitHub Actions-only project, development primarily involves:

```bash
# Validate workflow syntax
cat .github/workflows/free-tier-creation.yml

# Test workflow locally (requires act or similar tools)
# Note: Local testing requires all secrets to be configured
```

## Important Notes

- The project contains no traditional source code - it's entirely workflow-based
- All logic is contained within the GitHub Actions workflow file
- Configuration is done via environment variables and GitHub secrets
- The workflow is designed to be idempotent and can safely retry
- Capacity issues are expected and handled gracefully