# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Reporting a Vulnerability

We take the security of the Oracle Instance Creator project seriously. If you believe you have found a security vulnerability, please report it to us as described below.

**Please do not report security vulnerabilities through public GitHub issues.**

### How to Report

Please send an email to the repository maintainer with:

1. A description of the vulnerability
2. Steps to reproduce the issue
3. Potential impact assessment
4. Any suggested fixes or mitigations

### What to Expect

- **Response Time**: We aim to acknowledge receipt within 48 hours
- **Investigation**: We will investigate and validate the reported vulnerability
- **Updates**: You will receive regular updates on our progress
- **Resolution**: We will work to resolve confirmed vulnerabilities promptly

### Scope

This security policy covers:

- **Oracle Cloud Infrastructure (OCI) credential handling**
- **GitHub Actions workflow security**
- **SSH key management and storage**
- **Secret exposure in logs or artifacts**
- **Telegram notification security**

### Security Best Practices

When contributing to this project:

1. **Never commit credentials** (OCI keys, tokens, passwords)
2. **Use GitHub Secrets** for all sensitive data
3. **Validate input parameters** in shell scripts
4. **Follow principle of least privilege** for permissions
5. **Audit workflow permissions** regularly

### Responsible Disclosure

We follow responsible disclosure practices and will:

1. Work with you to understand and validate the vulnerability
2. Develop and test a fix
3. Release the fix and provide credit (if desired)
4. Document lessons learned to prevent similar issues

Thank you for helping keep the Oracle Instance Creator project secure!