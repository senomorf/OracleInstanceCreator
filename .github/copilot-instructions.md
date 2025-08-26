# GitHub Copilot PR Review Instructions

## Project Context
This is an Oracle Cloud Infrastructure (OCI) automation project that creates free tier instances using GitHub Actions. The system is optimized for cost efficiency and security.

## General Code Review Principles
**Apply comprehensive software engineering review for all changes**

### Code Quality & Best Practices:
- **Structure**: Clear organization, proper separation of concerns
- **Readability**: Self-documenting code with meaningful names
- **Maintainability**: Modular design, minimal complexity
- **Error Handling**: Proper validation, graceful failure handling
- **Documentation**: Clear comments explaining complex logic

### Security Analysis (All Types):
- **Input Validation**: Sanitize and validate all user inputs
- **Injection Prevention**: Protect against command/script injection
- **Authentication**: Proper credential handling and verification
- **Authorization**: Appropriate access controls and permissions
- **Data Protection**: Secure handling of sensitive information

### Performance & Efficiency:
- **Algorithm Complexity**: Optimal time/space complexity
- **Resource Usage**: Memory, CPU, and I/O efficiency
- **Caching**: Appropriate use of caching mechanisms
- **Bottleneck Identification**: Profile and optimize slow operations

### Testing & Quality Assurance:
- **Test Coverage**: Comprehensive unit and integration tests
- **Edge Cases**: Boundary conditions and error scenarios
- **Test Quality**: Clear, maintainable, and reliable tests
- **Regression Prevention**: Tests for previously fixed bugs

## GitHub Actions Cost Management
**Critical: Monitor usage to stay within free tier limits**

- **Current Usage**: 1,350 minutes/month from scheduled workflows
- **Target Maximum**: 1,800 minutes/month (90% of free tier)
- **Available Buffer**: 650 minutes for PR checks and manual runs
- **Billing**: Each run rounds up to minimum 1 minute

### Review Priorities for Actions Usage:
- Flag workflows running longer than 1 minute
- Identify unnecessary workflow triggers
- Suggest caching strategies for dependencies
- Recommend workflow optimizations to reduce runtime

## OCI Security Requirements
**Top Priority: Prevent credential exposure**

### Credential Safety Checklist:
- [ ] No OCI OCIDs, fingerprints, or keys in code
- [ ] SSH public/private keys properly handled
- [ ] Telegram tokens and user IDs secured
- [ ] All secrets use GitHub Secrets, never hardcoded

### Log Security Patterns:
- OCIDs should appear as `ocid1234...5678` (redacted)
- SSH keys/private keys should show `[REDACTED]`
- No sensitive parameters in workflow logs or artifacts

## Code Quality Standards

### Bash Script Requirements:
- **Performance Target**: <1 minute execution time
- **Error Handling**: Distinguish capacity issues (expected) from real failures
- **Validation**: All scripts must pass `bash -n script.sh`
- **Dependencies**: Use `--no-retry --connection-timeout 5 --read-timeout 15` for OCI CLI

### OCI-Specific Patterns:
- **OCID Validation**: Must match `^ocid1\.type\.[a-z0-9-]*\.[a-z0-9-]*\..+`
- **Flexible Shapes**: Must include `--shape-config {"ocpus": N, "memoryInGBs": N}`
- **Error Classification**:
  - Capacity/Rate Limit errors → return 0 (expected)
  - Internal/Network errors → retry same AD, then cycle
  - Auth/Config errors → return 1 (real failure)
  - Limit Exceeded → check if instance created despite error

### Multi-AD Cycling Logic:
- Retry transient errors 3x in same AD before cycling
- Handle comma-separated AD lists: `"AD-1,AD-2,AD-3"`
- Proper delay between retries (15 seconds default)

## Architecture Guidelines

### Performance Optimizations Applied:
- All OCI CLI commands use: `--no-retry --connection-timeout 5 --read-timeout 15`
- Target execution time: 17-18 seconds (current optimized performance)
- Avoid command substitution + logging anti-pattern

### Security Patterns:
- Single GitHub Actions job for all credentials (no artifacts)
- Parameter redaction in all log outputs
- SSH keys stored as GitHub Secrets only

## Review Focus Areas

### High Priority Issues:
1. **Credential Exposure**: Any hardcoded secrets or keys
2. **Logic Bugs**: Null checks, edge cases, algorithm errors
3. **Security Vulnerabilities**: Input validation, injection flaws, auth issues
4. **Cost Impact**: Workflows that could exceed usage limits
5. **Performance Regression**: Changes that slow execution >1 minute

### Medium Priority Issues:
1. **General Code Quality**: Structure, readability, maintainability
2. **Error Handling**: Both general patterns and OCI error classification
3. **Test Coverage**: Missing tests, poor test quality, edge cases
4. **Documentation**: Missing security considerations and code comments

### Low Priority Issues:
1. **Style**: Minor formatting inconsistencies
2. **Optimization**: Non-critical performance improvements
3. **Code Standards**: Adherence to project conventions

## Specific Review Commands

When reviewing PRs, apply both general and OCI-specific validation:

### General Code Validation:
```bash
# Validate bash syntax for all scripts
bash -n scripts/*.sh
bash -n tests/*.sh

# Check for common security issues
grep -r "eval\|exec" --include="*.sh" .
grep -r "wget\|curl.*http:" --include="*.sh" .

# Verify error handling patterns
grep -rn "set -e\|set -o pipefail" scripts/

# Check for hardcoded values
grep -r "localhost\|127.0.0.1\|password\|secret" --exclude-dir=.git .
```

### OCI-Specific Security Validation:
```bash
# Check for exposed OCI credentials
grep -r "ocid1\." --exclude-dir=.git .
grep -r "BEGIN.*KEY" --exclude-dir=.git .

# Verify workflow efficiency
grep -r "timeout" .github/workflows/

# Validate OCID formats in code
grep -r "ocid1" --include="*.sh" . | grep -v "ocid1234...5678"
```

## Success Metrics

### General Software Quality:
- **Code Quality**: Maintainable, readable, well-structured code
- **Security**: Zero vulnerabilities, proper input validation
- **Test Coverage**: Comprehensive tests with edge case coverage
- **Performance**: Efficient algorithms and resource usage
- **Documentation**: Clear code comments and architectural decisions

### OCI-Specific Goals:
- **Security**: Zero credential exposures, proper parameter redaction
- **Performance**: Maintain 17-18 second execution time for OCI operations
- **Cost**: Stay under 1,800 GitHub Actions minutes/month
- **Reliability**: Proper error classification and retry logic
- **Compliance**: OCID format validation, flexible shape configurations