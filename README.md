# Oracle Instance Creator

Automated Oracle Cloud Infrastructure (OCI) free tier instance creation using GitHub Actions.

## Overview

This project automatically attempts to create Oracle Cloud free tier instances using GitHub Actions workflows. It's designed to handle Oracle's capacity limitations gracefully and retry on a schedule when resources become available.

## Key Features

- **Automated Instance Creation**: Scheduled attempts to create OCI free tier instances
- **Smart Error Handling**: Distinguishes between capacity issues (expected) and genuine errors
- **Performance Optimized**: 93% execution time reduction (from ~2 minutes to ~17 seconds)
- **Proxy Support**: Full IPv4/IPv6 proxy support with URL-encoded credentials
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

**Proxy Support (Optional):**
- `OCI_PROXY_URL`: Authenticated proxy server URL
  - IPv4: `username:password@proxy.example.com:3128`
  - IPv6: `username:password@[::1]:3128`
  - Supports URL-encoded credentials for special characters
  - Example: `myuser:mypass@proxy.company.com:8080`

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

## Error Handling

The project implements intelligent error classification:

- **CAPACITY/RATE_LIMIT**: Expected for free tier (treated as success)
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