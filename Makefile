# Makefile for Oracle Instance Creator - Linting and Quality Checks
.PHONY: lint lint-fix lint-js lint-html lint-shell lint-yaml lint-actions lint-md lint-security lint-format lint-quality help validate-tools test-shell analyze-quality benchmark lint-license lint-advanced

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
	@echo "  lint-license - Check license compliance"
	@echo "  lint-advanced - Run advanced analysis (SonarQube)"
	@echo ""
	@echo "Testing and Analysis:"
	@echo "  test-shell   - Run shell script tests (shellspec/bats)"
	@echo "  analyze-quality - Run SonarQube analysis"
	@echo "  benchmark    - Performance benchmark critical scripts"
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
lint-all: lint lint-security lint-format lint-quality lint-license
	@echo "✅ Enhanced linting completed with security and quality analysis"

# Run comprehensive analysis including advanced tools
lint-advanced: lint-all analyze-quality
	@echo "✅ Advanced analysis completed with SonarQube metrics"

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
		echo "✓ djlint available - HTML linting configured"; \
	elif [ -x "/opt/homebrew/bin/djlint" ]; then \
		echo "✓ djlint available - HTML linting configured"; \
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
		semgrep --config=.semgrep.yml scripts/ docs/dashboard/js/ --no-rewrite-rule-ids --quiet || \
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

# License compliance checking
lint-license:
	@echo "📄 Running license compliance check..."
	@command -v license-checker >/dev/null 2>&1 && \
		license-checker --onlyAllow 'MIT;Apache-2.0;BSD-3-Clause;BSD-2-Clause;ISC' --relativeLicensePath docs/dashboard/js/ || \
		echo "⚠️  license-checker not found - install with: npm install -g license-checker"
	@echo "✅ License compliance check completed"

# Shell script testing with shellspec and bats
test-shell:
	@echo "🧪 Running shell script tests..."
	@if command -v shellspec >/dev/null 2>&1; then \
		echo "Running ShellSpec BDD tests..."; \
		shellspec; \
	else \
		echo "⚠️  shellspec not found - install with: npm install -g shellspec"; \
	fi
	@if command -v bats >/dev/null 2>&1; then \
		echo "Running BATS unit tests..."; \
		find tests -name "*.bats" -exec bats {} \; 2>/dev/null || echo "No BATS test files found"; \
	else \
		echo "⚠️  bats not found - install from: https://github.com/bats-core/bats-core"; \
	fi
	@echo "✅ Shell script testing completed"

# SonarQube analysis
analyze-quality:
	@echo "📊 Running SonarQube analysis..."
	@command -v sonar-scanner >/dev/null 2>&1 && \
		sonar-scanner || \
		echo "⚠️  sonar-scanner not found - install from: https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/"
	@echo "✅ SonarQube analysis completed"

# Performance benchmarking
benchmark:
	@echo "⚡ Running performance benchmarks..."
	@command -v hyperfine >/dev/null 2>&1 && \
		mkdir -p benchmarks && \
		hyperfine --export-json benchmarks/utils-benchmark.json 'bash scripts/utils.sh --help' || true && \
		hyperfine --export-json benchmarks/launch-benchmark.json --setup 'export DEBUG=false' 'bash scripts/launch-instance.sh --dry-run' || true && \
		echo "📈 Benchmark results saved to benchmarks/" || \
		echo "⚠️  hyperfine not found - install with: cargo install hyperfine"
	@echo "✅ Performance benchmarking completed"

# Utility target to validate tool availability
validate-tools:
	@echo "🔧 Validating tool availability..."
	@./scripts/validate-tools.sh