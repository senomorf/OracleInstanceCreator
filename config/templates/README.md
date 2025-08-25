# Configuration Templates

This directory contains pre-configured templates for common Oracle Cloud Infrastructure deployment scenarios.

## Available Templates

### Free Tier Templates

#### `singapore-arm-free.yml`
- **Region**: Asia Pacific (Singapore) - ap-singapore-1
- **Shape**: VM.Standard.A1.Flex (ARM-based)
- **Resources**: 4 OCPUs, 24 GB RAM (maximum free tier allocation)
- **Multi-AD**: 2 availability domains configured
- **Best for**: Most users, ARM instances are generally more available

#### `us-amd-free.yml`
- **Region**: US East (Ashburn) - us-ashburn-1
- **Shape**: VM.Standard.E2.1.Micro (AMD-based)
- **Resources**: 1 OCPU, 1 GB RAM (fixed shape)
- **Multi-AD**: 3 availability domains configured
- **Best for**: Users preferring AMD architecture or US-based instances

### Production Templates

#### `multi-region-example.yml`
- **Region**: Asia Pacific (Tokyo) - ap-tokyo-1
- **Shape**: VM.Standard3.Flex (production-grade)
- **Resources**: Configurable (example: 2 OCPUs, 16 GB RAM)
- **Features**: JSON logging, extended timeouts
- **Best for**: Production workloads (requires paid subscription)

## Usage Instructions

1. **Choose a template** that matches your requirements
2. **Copy the environment variables** to your GitHub Actions workflow
3. **Configure GitHub Secrets** as specified in each template
4. **Customize values** for your specific needs
5. **Test with preflight check**: Run `./scripts/preflight-check.sh`

## Template Selection Guide

### Free Tier Decision Matrix

| Factor | ARM (Singapore) | AMD (US) |
|--------|----------------|----------|
| **Performance** | 4 OCPUs, 24 GB | 1 OCPU, 1 GB |
| **Availability** | Generally higher | Moderate |
| **Region** | Asia-Pacific | North America |
| **Architecture** | ARM64 | x86_64 |
| **Boot Volume** | Up to 200 GB | Up to 200 GB |

### Key Considerations

#### ARM vs AMD
- **ARM (A1.Flex)**: Better resource allocation, usually more available
- **AMD (E2.1.Micro)**: Traditional x86 architecture, limited resources

#### Multi-AD Configuration
- Significantly improves success rates
- Automatically tries different availability domains
- Recommended for all configurations

#### Region Selection
- **Singapore**: Good free tier availability, Asia-Pacific location
- **US-Ashburn**: Mature region, North American location
- **Tokyo**: Premium region, often used for production

## Customization Tips

### Environment Variables
```yaml
# Core instance settings
OCI_SHAPE: "VM.Standard.A1.Flex"
OCI_OCPUS: "4"
OCI_MEMORY_IN_GBS: "24"

# Multi-AD configuration
OCI_AD: "AD-1,AD-2,AD-3"

# Timeout configuration
INSTANCE_VERIFY_MAX_CHECKS: "5"
RETRY_WAIT_TIME: "30"
```

### GitHub Secrets
All sensitive values should be stored as GitHub repository secrets:
- OCI authentication credentials
- SSH keys
- Telegram bot configuration

### Testing Configuration
Before deploying, use the preflight check:
```bash
./scripts/preflight-check.sh
```

## Advanced Configuration

### Structured Logging
For production monitoring:
```yaml
LOG_FORMAT: "json"
```

### Debug Mode
For troubleshooting:
```yaml
DEBUG: "true"
```

### Custom Image IDs
To use specific images:
```yaml
OCI_IMAGE_ID: "ocid1.image.oc1.region.aaaaaaa..."
```

## Regional Availability Domains

### Common AD Patterns
- **Singapore**: `fgaj:AP-SINGAPORE-1-AD-1`
- **US-Ashburn**: `ZGqs:US-ASHBURN-AD-1`
- **Tokyo**: `ctKs:AP-TOKYO-1-AD-1`
- **Frankfurt**: `unja:EU-FRANKFURT-1-AD-1`

Check your specific ADs with:
```bash
oci iam availability-domain list --compartment-id <tenancy-ocid>
```

## Support and Troubleshooting

1. **Validation errors**: Run preflight check for detailed diagnostics
2. **Capacity issues**: Try different regions or ADs
3. **Authentication problems**: Verify GitHub secrets configuration
4. **Image compatibility**: Ensure OS version matches your region

For more help, see the troubleshooting runbook in `docs/troubleshooting.md`.