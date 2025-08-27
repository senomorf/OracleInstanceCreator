# Contributing to Oracle Instance Creator

Thank you for your interest in contributing to the Oracle Instance Creator
project! This guide will help you understand our development workflow, code
quality standards, and contribution process.

## 📋 Table of Contents

- [Development Setup](#-development-setup)
- [Code Quality Standards](#-code-quality-standards)
- [Linting and Formatting](#-linting-and-formatting)
- [Testing](#-testing)
- [Submitting Changes](#-submitting-changes)
- [Issue Reporting](#-issue-reporting)

## 🔧 Development Setup

### Prerequisites

- **OCI CLI**: Oracle Cloud Infrastructure CLI tool
- **Bash 4.0+**: For shell scripts
- **Git**: Version control
- **GitHub CLI** (optional): For PR management

### Local Development

1. **Fork and Clone**
  ```bash
  git clone https://github.com/your-username/OracleInstanceCreator.git
  cd OracleInstanceCreator
  ```

2. **Create Feature Branch**
  ```bash
  git checkout -b feature/your-feature-name
  ```

3. **Run Local Tests**
  ```bash
  ./tests/run_new_tests.sh
  ```

## ⚡ Code Quality Standards

This project maintains high code quality through comprehensive linting and
automated checks.

### Linting Infrastructure

The project uses multiple linters to ensure code quality across different
file types:

#### 🐚 **Shell Scripts** (`.sh` files)
- **ShellCheck**: Static analysis for shell scripts
- **Configuration**: `.shellcheckrc`
- **Key Rules**:
  - Quote variables to prevent word splitting: `"$var"`
  - Separate declare and assign: `local var; var=$(command)`
  - Use `[[ ]]` for Bash conditionals

#### 📄 **Markdown** (`.md` files)
- **markdownlint**: Markdown style and syntax checker
- **Configuration**: `.markdownlint.json`
- **Key Rules**:
  - ATX-style headers (`# Header`)
  - Fenced code blocks
  - 120-character line limit (warnings only)

#### 📦 **JSON** (`.json` files)
- **JSON Linter**: Syntax validation
- **Key Rules**:
  - Valid JSON syntax
  - Proper indentation (2 spaces)

#### 🔧 **YAML** (`.yml`, `.yaml` files)
- **yamllint**: YAML syntax and style checker
- **Configuration**: `.yamllint.yml`
- **Key Rules**:
  - Document start markers (`---`)
  - 120-character line limit
  - Consistent indentation (2 spaces)

#### 🔍 **Code Duplication**
- **JSCPD**: Copy-paste detection
- **Configuration**: `.jscpd.json`
- **Thresholds**: 10+ lines or 50+ tokens

#### 🔐 **Security**
- **GitLeaks**: Secret detection
- **Scans**: API keys, tokens, passwords

#### ✏️ **File Formatting**
- **EditorConfig**: Consistent formatting
- **Configuration**: `.editorconfig`
- **Rules**: Line endings, indentation, final newlines

## 🔍 Linting and Formatting

### Running Linters Locally

**All Linters** (same as CI):
```bash
# Using GitHub's Super Linter (Docker required)
docker run --rm -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true \
  -v "$PWD":/tmp/lint github/super-linter:v4
```

**Individual Tools**:
```bash
# ShellCheck
shellcheck scripts/*.sh

# markdownlint
markdownlint "**/*.md"

# yamllint
yamllint .github/workflows/*.yml

# JSCPD (duplicate detection)
npx jscpd .

# EditorConfig
editorconfig-checker
```

### Fixing Common Issues

#### ShellCheck Fixes
```bash
# Bad: Unquoted variable
echo $USER

# Good: Quoted variable
echo "$USER"

# Bad: Masked return value
local result=$(command)

# Good: Separate declare/assign
local result
result=$(command)
```

#### Markdown Fixes
```bash
# Bad: Underline headers
Header
======

# Good: ATX headers
# Header

# Bad: Indented code
  code here

# Good: Fenced code
```bash
code here
```

```bash

### Pre-commit Hooks (Recommended)

Set up automatic linting before commits:
```bash
# Install pre-commit
pip install pre-commit

# Setup hooks (if .pre-commit-config.yaml exists)
pre-commit install
```

## 🧪 Testing

### Test Structure

- **Unit Tests**: `tests/test_*.sh`
- **Integration Tests**: `tests/test_integration.sh`
- **End-to-End Tests**: `tests/test_e2e_*.sh`

### Running Tests

```bash
# All tests
./tests/run_new_tests.sh

# Specific test file
bash tests/test_utils.sh

# Stress testing
bash tests/test_stress.sh
```

### Test Requirements

- All new features must include tests
- Maintain existing test coverage
- Tests should pass in CI environment

## 📝 Submitting Changes

### Pull Request Process

1. **Create Feature Branch**
  ```bash
  git checkout -b feature/descriptive-name
  ```

2. **Make Changes**
- Follow coding standards
- Add/update tests
- Update documentation

3. **Commit Changes**
  ```bash
  git add .
  git commit -m "feat: add descriptive commit message
  
  - Detailed explanation of changes
  - Reference any issues: Closes #123"
  ```

4. **Push and Create PR**
  ```bash
  git push origin feature/descriptive-name
  # Create PR via GitHub UI or GitHub CLI
  gh pr create --title "Feature: Description" --body "Detailed description"
  ```

### Commit Message Format

Follow conventional commits:
```text
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`

**Examples**:
- `feat(scripts): add retry logic for OCI API calls`
- `fix(dashboard): correct instance status display`
- `docs(readme): update installation instructions`

### PR Requirements

- [ ] All linting checks pass
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No breaking changes (or clearly documented)
- [ ] Follows project coding standards

## 🐛 Issue Reporting

### Bug Reports

Include:
- **Environment**: OS, OCI CLI version, region
- **Steps to Reproduce**: Exact commands/actions
- **Expected vs Actual Behavior**
- **Logs**: Relevant error messages
- **Configuration**: Sanitized config (no secrets)

### Feature Requests

Include:
- **Use Case**: Why this feature is needed
- **Proposed Solution**: How it should work
- **Alternatives**: Other approaches considered
- **Impact**: Who would benefit

## 📚 Additional Resources

- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/tools/oci-cli/)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [Project Architecture](docs/README.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

## 🤝 Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the code, not the person
- Help others learn and improve

## 📞 Getting Help

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and ideas
- **Documentation**: Check `docs/` directory first

Thank you for contributing to Oracle Instance Creator! 🚀
