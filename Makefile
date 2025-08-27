# Makefile for Oracle Instance Creator - Linting and Quality Checks
.PHONY: lint lint-fix lint-js lint-html lint-shell lint-yaml lint-actions lint-md help

# Default target
help:
	@echo "Oracle Instance Creator - Linting Commands"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  lint       - Run all linters"
	@echo "  lint-fix   - Auto-fix issues where possible"
	@echo "  lint-js    - Run ESLint on JavaScript files"
	@echo "  lint-html  - Run djlint on HTML files"
	@echo "  lint-shell - Run shellcheck on shell scripts"
	@echo "  lint-yaml  - Run yamllint on YAML files"
	@echo "  lint-actions - Run actionlint on GitHub workflows"
	@echo "  lint-md    - Run markdownlint on Markdown files"
	@echo "  help       - Show this help message"

# Run all linters
lint: lint-js lint-html lint-shell lint-yaml lint-actions lint-md
	@echo "✅ All linters completed"

# Auto-fix issues where possible
lint-fix:
	@echo "🔧 Auto-fixing linting issues..."
	@command -v eslint >/dev/null 2>&1 && eslint --fix docs/dashboard/js/*.js || echo "⚠️  ESLint not found"
	@if command -v djlint >/dev/null 2>&1; then djlint --reformat docs/dashboard/*.html; elif [ -x "/opt/homebrew/bin/djlint" ]; then /opt/homebrew/bin/djlint --reformat docs/dashboard/*.html; else echo "⚠️  djlint not found"; fi
	@command -v prettier >/dev/null 2>&1 && prettier --write "**/*.{json,yml,yaml,md}" || echo "⚠️  prettier not found"
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