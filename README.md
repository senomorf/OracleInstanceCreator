# OCI Free Tier Automation

[![GitHub Actions](https://github.com/senomorf/OracleInstanceCreator/workflows/OCI%20Free%20Tier%20Creation/badge.svg)](https://github.com/senomorf/OracleInstanceCreator/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OCI Compatible](https://img.shields.io/badge/OCI-Compatible-orange.svg)](https://cloud.oracle.com/)

Automated provisioning of Oracle Cloud free-tier instances (A1.Flex ARM & E2.1.Micro AMD) via GitHub Actions with parallel execution and smart retry logic.

## Features

- **Parallel provisioning** of both instance types (~20s execution)
- **Multi-AD cycling** with smart error handling and retry logic
- **Telegram notifications** and secure credential management
- **93% performance optimization** and comprehensive testing suite

## Quick Start

1. **Fork this repository**
2. **Add GitHub Secrets** (see Required Secrets below)
3. **Enable GitHub Actions** in repository settings
4. **Run workflow**: Actions → "OCI Free Tier Creation" → Run workflow

## Required Secrets

Add these secrets in your GitHub repository settings:

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

## Documentation

📖 **Comprehensive guides available:**

- 📊 **[Dashboard & Monitoring](docs/README.md)** - Real-time monitoring and analytics
- ⚙️ **[Configuration Guide](docs/configuration.md)** - Detailed setup and options
- 🔧 **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues and solutions  
- 👨‍💻 **[Development Guide](CLAUDE.md)** - Architecture and technical details

## How It Works

The system creates both free-tier instance types in parallel:
- **A1.Flex (ARM)**: 4 OCPUs, 24GB RAM - Better availability
- **E2.1.Micro (AMD)**: 1 OCPU, 1GB RAM - Traditional x86

Multi-AD cycling maximizes success rates. Capacity errors are expected and handled automatically.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

This project demonstrates advanced cloud automation patterns and Infrastructure-as-Code practices. Contributions welcome for additional cloud providers, enhanced error handling, or performance optimizations.