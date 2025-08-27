# Local Development Tools Guide

This guide outlines recommended formatters and static code analyzers to install locally for maintaining this project.

## Core Formatting Tools (Already Installed)

### JavaScript/TypeScript
- **Prettier**: Code formatter
  ```bash
  npm install -g prettier
  # Usage: prettier --write "**/*.js"
  ```
- **ESLint**: Linting and code quality
  ```bash
  npm install -g eslint@9.34.0
  # Usage: eslint --fix "**/*.js"
  ```

### Shell Scripts
- **shfmt**: Shell script formatter (already installed via Homebrew)
  ```bash
  # Already installed, usage:
  shfmt -w scripts/*.sh tests/*.sh
  ```
- **shellcheck**: Shell script static analysis (system package)
  ```bash
  # Usage: shellcheck scripts/*.sh tests/*.sh
  ```

### HTML/CSS
- **djlint**: HTML template linter and formatter
  ```bash
  pip install djlint
  # Usage: djlint --reformat docs/dashboard/*.html
  ```

### YAML/JSON
- **yamllint**: YAML linter
  ```bash
  pip install yamllint
  # Usage: yamllint .github/workflows/*.yml
  ```
- **Prettier** (also handles JSON/YAML formatting)

## Additional Recommended Tools

### 1. Advanced Code Analysis

#### **Codespell** - Spell checker for code
```bash
pip install codespell
# Usage: codespell -w  # fixes typos automatically
# Config: .codespellrc file
```

#### **Bandit** - Python security linter (for any Python scripts)
```bash
pip install bandit
# Usage: bandit -r . -f json
```

#### **Semgrep** - Multi-language static analysis
```bash
pip install semgrep
# Usage: semgrep --config=auto .
```

### 2. Documentation Tools

#### **Markdownlint** - Markdown linter
```bash
npm install -g markdownlint-cli
# Usage: markdownlint *.md docs/*.md
```

#### **Vale** - Prose linter for documentation
```bash
brew install vale
# Usage: vale docs/
# Needs .vale.ini configuration
```

### 3. Security & Secrets Detection

#### **Gitleaks** - Git secrets scanner
```bash
brew install gitleaks
# Usage: gitleaks detect --source . --verbose
```

#### **TruffleHog** - Secrets scanner
```bash
brew install truffleHog
# Usage: truffleHog git file://. --only-verified
```

### 4. Performance & Complexity

#### **SCC** - Source code counter with complexity metrics
```bash
brew install scc
# Usage: scc --by-file
```

#### **Lizard** - Code complexity analyzer
```bash
pip install lizard
# Usage: lizard scripts/ tests/
```

### 5. Container & Infrastructure

#### **Hadolint** - Dockerfile linter
```bash
brew install hadolint
# Usage: hadolint Dockerfile
```

#### **Checkov** - Infrastructure as Code scanner
```bash
pip install checkov
# Usage: checkov -d .github/workflows/
```

### 6. Git Hooks Integration

#### **Pre-commit** - Git hooks framework
```bash
pip install pre-commit
# Setup: pre-commit install
# Config: .pre-commit-config.yaml
```

Example `.pre-commit-config.yaml`:
```yaml
repos:
  - repo: local
    hooks:
      - id: prettier
        name: prettier
        entry: prettier --write
        language: system
        files: \.(js|json|yml|yaml|html)$
      
      - id: shfmt
        name: shfmt
        entry: shfmt -w
        language: system
        files: \.sh$
      
      - id: shellcheck
        name: shellcheck
        entry: shellcheck
        language: system
        files: \.sh$
      
      - id: eslint
        name: eslint
        entry: eslint --fix
        language: system
        files: \.js$
```

## Visual Studio Code Extensions (Recommended)

### Essential Extensions
- **Prettier - Code formatter**: `esbenp.prettier-vscode`
- **ESLint**: `dbaeumer.vscode-eslint`
- **shellcheck**: `timonwong.shellcheck`
- **YAML**: `redhat.vscode-yaml`
- **markdownlint**: `DavidAnson.vscode-markdownlint`

### Advanced Extensions
- **GitLens**: `eamodio.gitlens`
- **Todo Tree**: `Gruntfuggly.todo-tree`
- **Code Spell Checker**: `streetsidesoftware.code-spell-checker`
- **Error Lens**: `usernamehw.errorlens`

## Local Setup Script

Create a `setup-dev-tools.sh` script:

```bash
#!/bin/bash
echo "Setting up development tools..."

# Node.js tools
npm install -g prettier eslint@9.34.0 markdownlint-cli

# Python tools
pip install djlint yamllint codespell bandit checkov lizard

# Go tools (if Go is installed)
if command -v go &> /dev/null; then
    go install mvdan.cc/sh/v3/cmd/shfmt@latest
    go install github.com/rhymond/actionlint/cmd/actionlint@latest
fi

# Homebrew tools (macOS)
if command -v brew &> /dev/null; then
    brew install vale gitleaks hadolint scc
fi

echo "Development tools setup complete!"
echo "Don't forget to configure your editor with the recommended extensions."
```

## IDE Configuration Files

### `.editorconfig`
```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.{sh,bash}]
indent_size = 4

[*.{md,markdown}]
trim_trailing_whitespace = false
```

### `.vscode/settings.json`
```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "[shellscript]": {
    "editor.defaultFormatter": null
  },
  "eslint.enable": true,
  "files.associations": {
    "*.sh": "shellscript"
  },
  "shellcheck.enable": true,
  "yaml.validate": true,
  "yaml.schemas": {
    "https://json.schemastore.org/github-workflow.json": ".github/workflows/*.yml"
  }
}
```

## Automation Recommendations

### 1. Makefile Integration
Add to your `Makefile`:
```make
.PHONY: lint format check

lint:
    @echo "Running all linters..."
    eslint docs/dashboard/js/*.js
    shellcheck scripts/*.sh tests/*.sh
    djlint --check docs/dashboard/*.html
    yamllint .github/workflows/*.yml
    markdownlint *.md docs/*.md

format:
    @echo "Formatting all code..."
    prettier --write "**/*.{js,json,yml,yaml,html}"
    shfmt -w scripts/*.sh tests/*.sh
    djlint --reformat docs/dashboard/*.html

check: lint
    @echo "Running security and complexity checks..."
    gitleaks detect --source . --verbose || true
    lizard scripts/ tests/ || true
    codespell . || true
```

### 2. GitHub Actions Integration
These tools are already integrated into your workflows, but you can add more:

```yaml
# Add to .github/workflows/enhanced-quality.yml
- name: Run Lizard complexity analysis
  run: |
    pip install lizard
    lizard --length 15 --arguments 5 --CCN 10 scripts/ tests/

- name: Run Codespell
  run: |
    pip install codespell
    codespell --check-filenames --check-hidden
```

## Usage Tips

1. **Daily Development**: Run `make format && make lint` before committing
2. **Pre-commit Setup**: Use pre-commit hooks to automate formatting
3. **CI/CD Integration**: All these tools work well in GitHub Actions
4. **IDE Integration**: Configure your editor to run formatters on save
5. **Documentation**: Keep this guide updated as tools evolve

This setup will give you comprehensive code quality, security scanning, and formatting capabilities for your project.