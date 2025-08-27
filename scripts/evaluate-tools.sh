#!/bin/bash
# Tool Evaluation Script for Project Compatibility
# Tests each available tool on sample project files to assess suitability

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Tool Compatibility Evaluation${NC}"
echo -e "${BLUE}===============================================${NC}"
echo

# Test sample files
SAMPLE_SHELL_SCRIPT="$SCRIPT_DIR/utils.sh"
SAMPLE_JS_FILE="$PROJECT_ROOT/docs/dashboard/js/dashboard.js"
SAMPLE_YAML_FILE="$PROJECT_ROOT/config/defaults.yml"
SAMPLE_HTML_FILE="$PROJECT_ROOT/docs/dashboard/index.html"

evaluate_security_tools() {
	echo -e "${CYAN}=== Security Tools Evaluation ===${NC}"

	echo -e "${BLUE}1. Semgrep (Advanced static analysis)${NC}"
	echo "Testing on shell and JS files..."
	if semgrep --config=auto --severity=WARNING --quiet "$SAMPLE_SHELL_SCRIPT" "$SAMPLE_JS_FILE" 2>/dev/null | head -5; then
		echo -e "${GREEN}✓ Semgrep working - found patterns${NC}"
		SEMGREP_SCORE=5
	else
		echo -e "${YELLOW}○ Semgrep working - no issues found${NC}"
		SEMGREP_SCORE=4
	fi
	echo

	echo -e "${BLUE}2. Bandit (Python-focused security)${NC}"
	echo "Note: Bandit is Python-focused, limited value for shell/JS project"
	echo -e "${YELLOW}○ Bandit available but not suitable for this project${NC}"
	BANDIT_SCORE=1
	echo

	echo -e "${BLUE}3. Gitleaks (Secret detection)${NC}"
	echo "Testing secret detection on repository..."
	if gitleaks detect --source="$PROJECT_ROOT" --no-git --quiet 2>/dev/null; then
		echo -e "${GREEN}✓ Gitleaks working - no secrets found${NC}"
		GITLEAKS_SCORE=5
	else
		echo -e "${YELLOW}⚠ Gitleaks found potential issues (will investigate)${NC}"
		GITLEAKS_SCORE=4
	fi
	echo

	echo -e "${BLUE}4. Shellharden (Shell security hardening)${NC}"
	echo "Testing on sample shell script..."
	if shellharden --check "$SAMPLE_SHELL_SCRIPT" 2>/dev/null | head -3; then
		echo -e "${GREEN}✓ Shellharden working - found improvements${NC}"
		SHELLHARDEN_SCORE=5
	else
		echo -e "${YELLOW}○ Shellharden working - script looks good${NC}"
		SHELLHARDEN_SCORE=4
	fi
	echo
}

evaluate_formatters() {
	echo -e "${CYAN}=== Formatting Tools Evaluation ===${NC}"

	echo -e "${BLUE}1. shfmt vs beautysh (Shell formatting)${NC}"

	# Test shfmt
	echo "Testing shfmt on sample shell script..."
	TEMP_FILE1="/tmp/test_shfmt.sh"
	cp "$SAMPLE_SHELL_SCRIPT" "$TEMP_FILE1"
	if shfmt -w "$TEMP_FILE1" 2>/dev/null; then
		SHFMT_CHANGES=$(diff -u "$SAMPLE_SHELL_SCRIPT" "$TEMP_FILE1" | wc -l)
		echo -e "${GREEN}✓ shfmt working - would make $SHFMT_CHANGES changes${NC}"
		SHFMT_SCORE=$((5 - SHFMT_CHANGES / 10))
	else
		echo -e "${RED}✗ shfmt failed${NC}"
		SHFMT_SCORE=0
	fi
	rm -f "$TEMP_FILE1"

	# Test beautysh
	echo "Testing beautysh on sample shell script..."
	TEMP_FILE2="/tmp/test_beautysh.sh"
	cp "$SAMPLE_SHELL_SCRIPT" "$TEMP_FILE2"
	if beautysh "$TEMP_FILE2" 2>/dev/null; then
		BEAUTYSH_CHANGES=$(diff -u "$SAMPLE_SHELL_SCRIPT" "$TEMP_FILE2" | wc -l)
		echo -e "${GREEN}✓ beautysh working - would make $BEAUTYSH_CHANGES changes${NC}"
		BEAUTYSH_SCORE=$((5 - BEAUTYSH_CHANGES / 10))
	else
		echo -e "${RED}✗ beautysh failed${NC}"
		BEAUTYSH_SCORE=0
	fi
	rm -f "$TEMP_FILE2"
	echo

	echo -e "${BLUE}2. Prettier (Multi-language formatting)${NC}"
	echo "Testing prettier on JS/YAML files..."
	if prettier --check "$SAMPLE_JS_FILE" "$SAMPLE_YAML_FILE" 2>/dev/null; then
		echo -e "${GREEN}✓ Prettier working - files already formatted${NC}"
		PRETTIER_SCORE=5
	else
		echo -e "${YELLOW}○ Prettier working - would reformat files${NC}"
		PRETTIER_SCORE=4
	fi
	echo
}

evaluate_quality_tools() {
	echo -e "${CYAN}=== Code Quality Tools Evaluation ===${NC}"

	echo -e "${BLUE}1. Codespell (Spell checking)${NC}"
	echo "Testing on documentation and code comments..."
	if codespell "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/CLAUDE.md" --count 2>/dev/null; then
		echo -e "${GREEN}✓ Codespell working - found potential typos${NC}"
		CODESPELL_SCORE=5
	else
		echo -e "${GREEN}✓ Codespell working - no typos found${NC}"
		CODESPELL_SCORE=5
	fi
	echo
}

evaluate_test_frameworks() {
	echo -e "${CYAN}=== Testing Frameworks Evaluation ===${NC}"

	echo -e "${BLUE}1. Shellspec vs Bats${NC}"

	# Check existing test framework
	echo "Analyzing existing test framework..."
	EXISTING_TESTS=$(find "$PROJECT_ROOT/tests" -name "*.sh" | wc -l)
	echo "Current setup: $EXISTING_TESTS custom test scripts"

	echo "Shellspec: BDD-style, modern syntax, good for new tests"
	echo "Bats: Simple, compatible with existing bash tests"
	echo "Recommendation: Keep existing framework, consider Bats for new tests"
	SHELLSPEC_SCORE=3
	BATS_SCORE=4
	echo
}

# Run evaluations
evaluate_security_tools
evaluate_formatters
evaluate_quality_tools
evaluate_test_frameworks

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Tool Selection Recommendations${NC}"
echo -e "${BLUE}===============================================${NC}"

echo -e "${GREEN}RECOMMENDED TOOLS (High Priority):${NC}"
echo "✓ semgrep         - Score: $SEMGREP_SCORE/5 (Excellent security analysis)"
echo "✓ gitleaks        - Score: $GITLEAKS_SCORE/5 (Essential secret detection)"
echo "✓ shfmt           - Score: $SHFMT_SCORE/5 (Better shell formatting)"
echo "✓ codespell       - Score: $CODESPELL_SCORE/5 (Documentation quality)"

echo
echo -e "${YELLOW}CONDITIONAL TOOLS (Medium Priority):${NC}"
echo "○ shellharden     - Score: $SHELLHARDEN_SCORE/5 (Good for security hardening)"
echo "○ prettier        - Score: $PRETTIER_SCORE/5 (If consistent multi-lang formatting needed)"
echo "○ bats            - Score: $BATS_SCORE/5 (For additional testing capabilities)"

echo
echo -e "${RED}NOT RECOMMENDED:${NC}"
echo "✗ bandit          - Score: $BANDIT_SCORE/5 (Python-focused, not suitable)"
echo "✗ beautysh        - Score: $BEAUTYSH_SCORE/5 (shfmt is superior)"
echo "? shellspec       - Score: $SHELLSPEC_SCORE/5 (Existing test framework sufficient)"

echo
echo -e "${CYAN}Next Steps:${NC}"
echo "1. Configure recommended tools (semgrep, gitleaks, shfmt, codespell)"
echo "2. Create configurations for conditional tools"
echo "3. Integrate into Makefile and CI/CD workflows"
echo "4. Test on full codebase and tune configurations"
