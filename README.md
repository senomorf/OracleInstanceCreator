# OCI Free Tier Automation

[![GitHub Actions](https://github.com/senomorf/OracleInstanceCreator/workflows/OCI%20Free%20Tier%20Creation/badge.svg)](https://github.com/senomorf/OracleInstanceCreator/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OCI Compatible](https://img.shields.io/badge/OCI-Compatible-orange.svg)](https://cloud.oracle.com/)

Automated provisioning of Oracle Cloud free-tier instances (A1.Flex ARM & E2.1.Micro AMD) via GitHub Actions with parallel execution and smart retry logic.

## Features

- **Parallel provisioning** of both instance types (~20s execution)
- **Multi-AD cycling** for higher success rates  
- **Smart error handling** with transient error retry
- **Telegram notifications** with complete instance details (IDs, IPs, connection info)
- **Secure credential management** via GitHub Secrets
- **93% performance optimization** through CLI tuning
- **Proxy support** for corporate environments
- **Circuit breaker pattern** to avoid failed availability domains
- **Comprehensive testing** with 33 automated test cases

## Quick Start

1. **Fork this repository**
2. **Add GitHub Secrets** (see Configuration below)
3. **Enable GitHub Actions** in repository settings
4. **Run workflow**: Actions → "OCI Free Tier Creation" → Run workflow

## Configuration

### Required GitHub Secrets

| Secret | Description | Example |
|--------|-------------|---------|
| `OCI_USER_OCID` | User OCID | `ocid1.user.oc1..aaa...` |
| `OCI_KEY_FINGERPRINT` | API key fingerprint | `aa:bb:cc:dd:ee:ff...` |
| `OCI_TENANCY_OCID` | Tenancy OCID | `ocid1.tenancy.oc1..aaa...` |
| `OCI_REGION` | Region identifier | `ap-singapore-1` |
| `OCI_PRIVATE_KEY` | Private key content | `-----BEGIN PRIVATE KEY-----...` |
| `OCI_SUBNET_ID` | Subnet OCID | `ocid1.subnet.oc1..aaa...` |
| `INSTANCE_SSH_PUBLIC_KEY` | SSH public key | `ssh-rsa AAAA...` |
| `TELEGRAM_TOKEN` | Bot token | `123456:ABC-DEF...` |
| `TELEGRAM_USER_ID` | User ID | `123456789` |

### Optional Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OCI_COMPARTMENT_ID` | Tenancy | Compartment OCID |
| `OCI_IMAGE_ID` | Auto-detect | Image OCID |
| `OCI_PROXY_URL` | None | `user:pass@proxy:3128` |
| `OCI_AD` | AD-1 | Comma-separated ADs |
| `BOOT_VOLUME_SIZE` | 50 | Boot disk size in GB |

## How It Works

The system executes both instance types in parallel for maximum efficiency:

**A1.Flex (ARM Architecture)**
- 4 OCPUs, 24GB RAM
- Instance name: `a1-flex-sg`
- Better availability than AMD

**E2.1.Micro (AMD Architecture)**  
- 1 OCPU, 1GB RAM
- Instance name: `e2-micro-sg`
- Traditional x86 architecture

Each shape independently cycles through configured availability domains until successful or capacity unavailable. The parallel approach maximizes your chances of securing at least one free-tier instance.

## Deployment Scenarios

- **Both instances created**: Complete success ✅✅
- **One instance created**: Partial success ✅⏳  
- **Zero instances created**: Retry on schedule ⏳⏳

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Capacity errors** | Normal - Oracle has limited free resources. Workflow retries automatically every 6 hours |
| **Authentication failed** | Verify API key fingerprint and private key format in GitHub Secrets |
| **Timeout after 55s** | Built-in protection to prevent excessive GitHub Actions billing |
| **"Out of host capacity"** | Expected during peak usage - not a configuration error |
| **Proxy connection issues** | Check proxy URL format: `username:password@proxy.example.com:3128` |

## Performance

- **Execution time**: ~20-25 seconds for both shapes in parallel
- **GitHub Actions billing**: Single job execution (1 minute minimum charge)
- **Monthly usage**: ~2,880 minutes at default */6 schedule ⚠️ EXCEEDS FREE TIER
- **Optimization**: 93% improvement via OCI CLI flag tuning

## Local Testing

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Validate configuration (requires environment variables)
./scripts/validate-config.sh

# Test parallel execution
./scripts/launch-parallel.sh

# Run test suites
./tests/test_integration.sh    # 9 tests
./tests/test_proxy.sh         # 15 tests
```

## Security

- All credentials managed via GitHub Secrets (never committed)
- Debug logging automatically redacts sensitive information
- Secure file permissions (600/700) on temporary files
- Network proxy support with URL-encoded credentials

## Advanced Features

- **Circuit breaker**: Automatically skips consistently failing availability domains
- **Exponential backoff**: Smart retry delays for transient errors
- **Instance verification**: Re-checks creation after LimitExceeded errors
- **Multi-region support**: Works with any OCI region
- **Comprehensive logging**: Structured output for debugging

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Complete project architecture, patterns, and development guide
- **[Notification Policy](CLAUDE.md#telegram-notification-policy)** - Clear guidelines on when notifications are sent
- **[Linter Configuration](CLAUDE.md#linter-configuration-policy)** - Code quality focus over arbitrary style rules

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

This project demonstrates advanced cloud automation patterns and Infrastructure-as-Code practices. Contributions welcome for additional cloud providers, enhanced error handling, or performance optimizations.