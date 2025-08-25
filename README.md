# Oracle Instance Creator (Parallel)

Automated Oracle Cloud Infrastructure (OCI) free tier instance creation using GitHub Actions with **parallel execution** for both free tier shapes.

## Overview

This project automatically attempts to create **BOTH** Oracle Cloud free tier instances simultaneously using GitHub Actions workflows. It maximizes your free tier utilization by creating both ARM (A1.Flex) and AMD (E2.1.Micro) instances in parallel, giving you the best chance of securing these limited resources when capacity becomes available.

## Key Features

- **Parallel Free Tier Creation**: Simultaneously attempts both ARM (A1.Flex) and AMD (E2.1.Micro) shapes
- **GitHub Actions Billing Optimized**: Single job execution keeps billing at 1 minute per run
- **Maximum Resource Utilization**: Creates both free tier instances when capacity allows
- **Smart Error Handling**: Distinguishes between capacity issues (expected) and genuine errors
- **Performance Optimized**: ~20-25 seconds execution time for both shapes in parallel
- **Timeout Protection**: 55-second safety limit prevents 2-minute billing charges
- **Telegram Notifications**: Success/failure alerts with shape-specific details
- **Modular Architecture**: Shape-agnostic scripts support any OCI configuration

## Performance Optimizations

### Critical Performance Breakthrough
- **Original**: ~2 minutes execution time (single shape)
- **Parallel Optimized**: ~20-25 seconds execution time (both shapes)  
- **Per-shape Performance**: ~17-18 seconds each (runs in parallel)
- **Improvement**: 93% reduction via OCI CLI flag optimization + parallel execution

### Optimization Details
The major performance improvement was achieved by optimizing OCI CLI flags:
- `--no-retry`: Eliminates exponential backoff retry logic (5 attempts with increasing delays)
- `--connection-timeout 5`: Fast failure on connection issues (vs 10s default)
- `--read-timeout 15`: Quick timeout on slow responses (vs 60s default)

**Why this works**: Oracle free tier capacity errors are expected and handled gracefully by our error handling logic. The automatic retry mechanism was counterproductive since we treat capacity issues as success conditions.

## Parallel Execution Strategy

### Free Tier Instance Configurations

**A1.Flex (ARM) Instance:**
- **Shape**: VM.Standard.A1.Flex
- **OCPUs**: 4 
- **Memory**: 24GB
- **Instance Name**: a1-flex-sg

**E2.1.Micro (AMD) Instance:**
- **Shape**: VM.Standard.E2.1.Micro
- **OCPUs**: 1 (fixed shape)
- **Memory**: 1GB (fixed shape) 
- **Instance Name**: e2-micro-sg

### Execution Results

**Success Scenarios:**
- **Both instances created**: Maximum free tier achieved ✅✅
- **One instance created**: Partial success, retry for remaining shape ✅⏳
- **Zero instances created**: Capacity unavailable, retry both ⏳⏳

### GitHub Actions Billing Optimization

**Key Insight**: GitHub Actions rounds each job UP to the nearest minute.

**Single Job Strategy:**
- Both shapes attempted in parallel within ONE job
- Execution time: ~20-25 seconds
- Billing time: 1 minute per run
- **Monthly cost at */6 schedule**: ~7,200 minutes (~$52/month)

**Alternative Matrix Strategy (NOT used):**
- Would create 2 separate jobs (1 per shape)
- Execution time: ~17 seconds each
- Billing time: 2 minutes per run (2 jobs × 1 min each)
- **Monthly cost**: ~14,400 minutes (~$104/month) ❌

### Timeout Protection
- **Hard limit**: 55 seconds maximum execution
- **Purpose**: Prevents 2-minute billing if something goes wrong
- **Implementation**: Automatic process termination with cleanup

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
./scripts/launch-parallel.sh     # Launch both shapes in parallel  
./scripts/launch-instance.sh     # Launch single shape (with env vars set)
./scripts/notify.sh test         # Test notifications
```

## Architecture

### File Structure
```
├── .github/workflows/free-tier-creation.yml  # Main GitHub Actions workflow (parallel)
├── scripts/
│   ├── utils.sh                              # Common utilities & OCI CLI wrappers
│   ├── validate-config.sh                    # Configuration validation
│   ├── setup-oci.sh                          # OCI CLI setup
│   ├── setup-ssh.sh                          # SSH key configuration
│   ├── launch-parallel.sh                    # Parallel orchestrator for both shapes
│   ├── launch-instance.sh                    # Shape-agnostic instance creation logic
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
3. Normal parallel execution should complete in 20-25 seconds (both shapes)
4. Timeout protection kicks in at 55 seconds to prevent 2-minute billing

### Debug Mode
Enable verbose output for troubleshooting:
```bash
gh workflow run free-tier-creation.yml --field verbose_output=true
```

## Development

See [CLAUDE.md](CLAUDE.md) for detailed development guidance, technical patterns, and lessons learned.

## License

This project is for educational and personal use with Oracle Cloud free tier resources.