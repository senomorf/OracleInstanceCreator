# Makefile for Oracle Instance Creator - Linting and Quality Checks
.PHONY: lint lint-fix lint-js lint-html lint-shell lint-yaml lint-actions lint-md lint-security lint-format lint-quality help validate-tools

# Default target
help:
	@echo "Oracle Instance Creator - Linting Commands"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  lint         - Run all linters (traditional)"
	@echo "  lint-all     - Run enhanced linting with security and quality tools"
	@echo "  lint-fix     - Auto-fix issues where possible"
	@echo "  lint-security - Run security analysis tools"
	@echo "  lint-format  - Run formatting tools"
	@echo "  lint-quality - Run code quality tools"
	@echo ""
	@echo "Individual tools:"
	@echo "  lint-js      - Run ESLint on JavaScript files"
	@echo "  lint-html    - Run djlint on HTML files"
	@echo "  lint-shell   - Run shellcheck on shell scripts"
	@echo "  lint-yaml    - Run yamllint on YAML files"
	@echo "  lint-actions - Run actionlint on GitHub workflows"
	@echo "  lint-md      - Run markdownlint on Markdown files"
	@echo ""
	@echo "Utility targets:"
	@echo "  validate-tools - Check availability of all linting tools"
	@echo "  help          - Show this help message"

# Run traditional linters (backward compatibility)
lint: lint-js lint-html lint-shell lint-yaml lint-actions lint-md
	@echo "✅ All traditional linters completed"

# Run enhanced linting with security and quality tools
lint-all: lint lint-security lint-format lint-quality
	@echo "✅ Enhanced linting completed with security and quality analysis"

# Auto-fix issues where possible
lint-fix:
	@echo "🔧 Auto-fixing linting issues..."
	@command -v eslint >/dev/null 2>&1 && eslint --fix docs/dashboard/js/*.js || echo "⚠️  ESLint not found"
	@if command -v djlint >/dev/null 2>&1; then djlint --reformat docs/dashboard/*.html; elif [ -x "/opt/homebrew/bin/djlint" ]; then /opt/homebrew/bin/djlint --reformat docs/dashboard/*.html; else echo "⚠️  djlint not found"; fi
	@command -v prettier >/dev/null 2>&1 && prettier --write "**/*.{json,yml,yaml,md}" || echo "⚠️  prettier not found"
	@command -v shfmt >/dev/null 2>&1 && shfmt -w scripts/*.sh tests/*.sh || echo "⚠️  shfmt not found"
	@echo "✅ Auto-fix completed"

# JavaScript linting
lint-js:
	@echo "🔍 Running ESLint on JavaScript files..."
	@command -v eslint >/dev/null 2>&1 && \
		eslint docs/dashboard/js/*.js || \
		echo "❌ ESLint not found - install with: npm install -g eslint"

# HTML linting
lint-html:
	@echo "🔍 Running djlint on HTML files..."
	@if command -v djlint >/dev/null 2>&1; then \
		djlint --check docs/dashboard/*.html; \
	elif [ -x "/opt/homebrew/bin/djlint" ]; then \
		/opt/homebrew/bin/djlint --check docs/dashboard/*.html; \
	else \
		echo "❌ djlint not found - install with: pip install djlint"; \
	fi

# Shell script linting  
lint-shell:
	@echo "🔍 Running shellcheck on shell scripts..."
	@command -v shellcheck >/dev/null 2>&1 && \
		shellcheck scripts/*.sh tests/*.sh || \
		echo "❌ shellcheck not found - install with: brew install shellcheck"

# YAML linting
lint-yaml:
	@echo "🔍 Running yamllint on YAML files..."
	@command -v yamllint >/dev/null 2>&1 && \
		yamllint -c .yamllint.yml .github/workflows/*.yml config/*.yml || \
		echo "❌ yamllint not found - install with: pip install yamllint"

# GitHub Actions linting
lint-actions:
	@echo "🔍 Running actionlint on GitHub workflows..."
	@command -v actionlint >/dev/null 2>&1 && \
		actionlint .github/workflows/*.yml || \
		echo "❌ actionlint not found - install with: brew install actionlint"

# Markdown linting
lint-md:
	@echo "🔍 Running markdownlint on Markdown files..."
	@command -v markdownlint >/dev/null 2>&1 && \
		markdownlint *.md docs/*.md || \
		echo "❌ markdownlint not found - install with: npm install -g markdownlint-cli"

# Security analysis tools
lint-security:
	@echo "🔒 Running security analysis tools..."
	@echo "📊 Running semgrep security analysis..."
	@command -v semgrep >/dev/null 2>&1 && \
		semgrep --config=.semgrep.yml scripts/ docs/dashboard/js/ || \
		echo "⚠️  semgrep not found - install with: pip install semgrep"
	@echo "🕵️  Running gitleaks secret detection..."
	@command -v gitleaks >/dev/null 2>&1 && \
		gitleaks detect --source=. --config=.gitleaks.toml --no-git || \
		echo "⚠️  gitleaks not found - install with: brew install gitleaks"
	@echo "🛡️  Running shellharden security check..."
	@command -v shellharden >/dev/null 2>&1 && \
		shellharden --check scripts/*.sh || \
		echo "⚠️  shellharden not found - install with: brew install shellharden"
	@echo "✅ Security analysis completed"

# Formatting tools
lint-format:
	@echo "🎨 Running formatting validation..."
	@echo "📝 Checking shell script formatting..."
	@command -v shfmt >/dev/null 2>&1 && \
		shfmt -d scripts/*.sh tests/*.sh || \
		echo "⚠️  shfmt not found - install with: brew install shfmt"
	@echo "💅 Checking multi-language formatting..."
	@command -v prettier >/dev/null 2>&1 && \
		prettier --check "**/*.{js,json,yml,yaml,md}" || \
		echo "⚠️  prettier not found - install with: npm install -g prettier"
	@echo "✅ Formatting validation completed"

# Code quality tools
lint-quality:
	@echo "📚 Running code quality tools..."
	@echo "📖 Running spell checking..."
	@command -v codespell >/dev/null 2>&1 && \
		codespell . || \
		echo "⚠️  codespell not found - install with: pip install codespell"
	@echo "🔍 Running duplicate code detection..."
	@command -v jscpd >/dev/null 2>&1 && \
		jscpd . || \
		echo "⚠️  jscpd not available - checking existing setup..."
	@echo "✅ Code quality analysis completed"

# Utility target to validate tool availability
validate-tools:
	@echo "🔧 Validating tool availability..."
	@./scripts/validate-tools.sh