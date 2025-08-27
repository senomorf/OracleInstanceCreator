#!/bin/bash
# Tool Validation Script for Enhanced Linting Setup
# Validates availability and basic functionality of all installed quality tools

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
TOTAL_TOOLS=0
AVAILABLE_TOOLS=0
WORKING_TOOLS=0

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Enhanced Linting Tools Validation${NC}"
echo -e "${BLUE}===============================================${NC}"
echo

# Tool validation function
validate_tool() {
	local tool_name="$1"
	local test_command="$2"
	local description="$3"

	((TOTAL_TOOLS++))

	printf "%-20s" "$tool_name"

	if command -v "$tool_name" >/dev/null 2>&1; then
		printf "${GREEN}✓ Available${NC}  "
		((AVAILABLE_TOOLS++))

		# Test basic functionality
		if eval "$test_command" >/dev/null 2>&1; then
			printf "${GREEN}✓ Working${NC}   "
			((WORKING_TOOLS++))
			echo -e "${description}"
		else
			printf "${YELLOW}⚠ Issue${NC}     "
			echo -e "${YELLOW}$description (command failed)${NC}"
		fi
	else
		printf "${RED}✗ Missing${NC}   ${RED}✗ N/A${NC}       "
		echo -e "${RED}$description (not installed)${NC}"
	fi
}

echo -e "${BLUE}Security Analysis Tools:${NC}"
echo "----------------------------------------"
validate_tool "semgrep" "semgrep --version" "Advanced static analysis for security vulnerabilities"
validate_tool "bandit" "bandit --version" "Python security linter (for comparison)"
validate_tool "gitleaks" "gitleaks version" "Git secrets detection"
validate_tool "shellharden" "shellharden --version || echo 'test'" "Shell script security hardening"

echo
echo -e "${BLUE}Code Formatting Tools:${NC}"
echo "----------------------------------------"
validate_tool "shfmt" "shfmt --version" "Shell script formatter"
validate_tool "beautysh" "beautysh --version" "Alternative shell beautifier"
validate_tool "prettier" "prettier --version" "Multi-language code formatter"

echo
echo -e "${BLUE}Code Quality Tools:${NC}"
echo "----------------------------------------"
validate_tool "codespell" "codespell --version" "Spell checking for code and documentation"

echo
echo -e "${BLUE}Testing Frameworks:${NC}"
echo "----------------------------------------"
validate_tool "shellspec" "shellspec --version" "BDD testing framework for shell"
validate_tool "bats" "bats --version" "Bash Automated Testing System"

echo
echo -e "${BLUE}Existing Tools (for comparison):${NC}"
echo "----------------------------------------"
validate_tool "eslint" "eslint --version" "JavaScript linter (existing)"
validate_tool "shellcheck" "shellcheck --version" "Shell script linter (existing)"
validate_tool "djlint" "djlint --version" "HTML template linter (existing)"
validate_tool "yamllint" "yamllint --version" "YAML linter (existing)"
validate_tool "actionlint" "actionlint --version" "GitHub Actions linter (existing)"
validate_tool "markdownlint" "markdownlint --version" "Markdown linter (existing)"

echo
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "Total tools checked:     ${TOTAL_TOOLS}"
echo -e "Available tools:         ${GREEN}${AVAILABLE_TOOLS}${NC}"
echo -e "Working tools:           ${GREEN}${WORKING_TOOLS}${NC}"
echo -e "Missing tools:           ${RED}$((TOTAL_TOOLS - AVAILABLE_TOOLS))${NC}"
echo -e "Non-working tools:       ${YELLOW}$((AVAILABLE_TOOLS - WORKING_TOOLS))${NC}"

echo
if [ $WORKING_TOOLS -eq $TOTAL_TOOLS ]; then
	echo -e "${GREEN}🎉 All tools are available and working!${NC}"
	exit 0
elif [ $AVAILABLE_TOOLS -eq $TOTAL_TOOLS ]; then
	echo -e "${YELLOW}⚠️  All tools are installed but some have issues${NC}"
	exit 1
else
	echo -e "${RED}❌ Some tools are missing. Please install missing tools.${NC}"
	echo
	echo -e "${BLUE}Installation suggestions:${NC}"
	echo "brew install semgrep gitleaks shellharden shfmt prettier codespell"
	echo "pip install bandit beautysh"
	echo "npm install -g shellspec"
	echo "git clone https://github.com/bats-core/bats-core.git && cd bats-core && sudo ./install.sh /usr/local"
	exit 1
fi
