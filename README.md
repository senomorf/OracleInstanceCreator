# Oracle Instance Creator

Automated Oracle Cloud Infrastructure (OCI) free tier instance creation using GitHub Actions.

## Overview

This project automatically attempts to create Oracle Cloud free tier instances using GitHub Actions workflows. It's designed to handle Oracle's capacity limitations gracefully and retry on a schedule when resources become available.

## Key Features

- **Automated Instance Creation**: Scheduled attempts to create OCI free tier instances
- **Multi-AD Cycling**: Automatically tries multiple availability domains for higher success rates
- **Smart Error Handling**: Distinguishes between capacity issues (expected) and genuine errors
- **Instance Recovery**: Auto-restart failed instances with `RESTORE_INSTANCE` configuration
- **Enhanced Validation**: Comprehensive pre-flight checks and configuration validation
- **Performance Optimized**: 93% execution time reduction (from ~2 minutes to ~17 seconds)
- **Telegram Notifications**: Success/failure alerts via Telegram bot
- **Modular Architecture**: Separate scripts for different functions (validation, setup, launch)

## Performance Optimizations

### Critical Performance Breakthrough
- **Original**: ~2 minutes execution time
- **Optimized**: ~17-18 seconds execution time  
- **Improvement**: 93% reduction via OCI CLI flag optimization

### Optimization Details
The major performance improvement was achieved by optimizing OCI CLI flags:
- `--no-retry`: Eliminates exponential backoff retry logic (5 attempts with increasing delays)
- `--connection-timeout 5`: Fast failure on connection issues (vs 10s default)
- `--read-timeout 15`: Quick timeout on slow responses (vs 60s default)

**Why this works**: Oracle free tier capacity errors are expected and handled gracefully by our error handling logic. The automatic retry mechanism was counterproductive since we treat capacity issues as success conditions.

## Quick Start

### Required GitHub Secrets
Configure these secrets in your GitHub repository:

**OCI Configuration:**
- `OCI_USER_OCID`: Your Oracle user OCID
- `OCI_KEY_FINGERPRINT`: API key fingerprint
- `OCI_TENANCY_OCID`: Tenancy OCID  
- `OCI_REGION`: OCI region (e.g., "ap-singapore-1")
- `OCI_PRIVATE_KEY`: Private API key content
- `OCI_COMPARTMENT_ID`: Compartment OCID (optional)
- `OCI_SUBNET_ID`: Subnet OCID
- `OCI_IMAGE_ID`: Image OCID (optional, auto-detected)

**Instance Configuration:**
- `INSTANCE_SSH_PUBLIC_KEY`: SSH public key for instance access

**Notifications:**
- `TELEGRAM_TOKEN`: Telegram bot token
- `TELEGRAM_USER_ID`: Your Telegram user ID

### Manual Execution
```bash
# Run workflow manually with debug output
gh workflow run free-tier-creation.yml --field verbose_output=true --field send_notifications=false

# Monitor execution
gh run watch <run-id>
```

### Local Testing
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Test individual components (requires environment variables)
./scripts/validate-config.sh      # Validate configuration
./scripts/setup-oci.sh           # Setup OCI authentication  
./scripts/launch-instance.sh     # Launch instance
./scripts/notify.sh test         # Test notifications
```

## Architecture

### File Structure
```
├── .github/workflows/free-tier-creation.yml  # Main GitHub Actions workflow
├── scripts/
│   ├── utils.sh                              # Common utilities & OCI CLI wrappers
│   ├── validate-config.sh                    # Configuration validation
│   ├── setup-oci.sh                          # OCI CLI setup
│   ├── setup-ssh.sh                          # SSH key configuration
│   ├── launch-instance.sh                    # Instance creation logic
│   └── notify.sh                             # Telegram notifications
├── config/
│   ├── instance-profiles.yml                 # Pre-defined configurations
│   ├── defaults.yml                          # Default values
│   └── regions.yml                           # Region reference
├── docs/
│   └── configuration.md                      # Detailed configuration guide
├── CLAUDE.md                                 # Development guidance
└── README.md                                 # This file
```

## Advanced Features (New in 2025-08-25)

### Multi-Availability Domain Support
Configure multiple ADs for automatic failover:
```yaml
# Single AD (existing behavior)
OCI_AD: "fgaj:AP-SINGAPORE-1-AD-1"

# Multi-AD cycling (new feature)
OCI_AD: "fgaj:AP-SINGAPORE-1-AD-1,fgaj:AP-SINGAPORE-1-AD-2,fgaj:AP-SINGAPORE-1-AD-3"
```

### Enhanced Configuration Options
New environment variables available in GitHub Actions workflow:
- `BOOT_VOLUME_SIZE`: Boot disk size in GB (default: 50, minimum: 50)
- `RECOVERY_ACTION`: Instance recovery behavior (default: "RESTORE_INSTANCE")
- `LEGACY_IMDS_ENDPOINTS`: IMDS compatibility (default: "false")  
- `RETRY_WAIT_TIME`: Wait time between AD attempts in seconds (default: 30)

### Instance Re-verification
The system now automatically verifies instance creation after `LimitExceeded` errors, preventing false failures when Oracle creates instances despite returning errors.

## Error Handling

The project implements intelligent error classification:

- **CAPACITY/RATE_LIMIT**: Expected for free tier (treated as success)
- **LIMIT_EXCEEDED**: Special handling with instance re-verification
- **INTERNAL_ERROR**: Oracle internal/gateway errors (retry-able)
- **AUTH**: Authentication errors (triggers alert)
- **CONFIG**: Invalid configuration (triggers alert)  
- **NETWORK**: Connectivity issues (triggers alert)

## Troubleshooting

### Performance Issues
If workflow takes longer than expected:
1. Check for missing optimization flags in OCI CLI commands
2. Expected debug output should show: `oci --debug --no-retry --connection-timeout 5 --read-timeout 15`
3. Normal execution should complete in 17-20 seconds

### Debug Mode
Enable verbose output for troubleshooting:
```bash
gh workflow run free-tier-creation.yml --field verbose_output=true
```

## Development

See [CLAUDE.md](CLAUDE.md) for detailed development guidance, technical patterns, and lessons learned.

## License

This project is for educational and personal use with Oracle Cloud free tier resources.