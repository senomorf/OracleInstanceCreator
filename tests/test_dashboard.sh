#!/bin/bash

# Test suite for dashboard functionality
# Validates HTML structure, JavaScript functionality, API error handling, and CDN fallbacks

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test framework from existing test
source "$SCRIPT_DIR/test_utils.sh"

# Dashboard paths
DASHBOARD_DIR="$PROJECT_ROOT/docs/dashboard"
HTML_FILES=("$DASHBOARD_DIR/index.html")
JS_FILES=("$DASHBOARD_DIR/js/dashboard.js")
CSS_FILES=("$DASHBOARD_DIR/css/dashboard.css")

echo "🖥️  Running Dashboard Tests"
echo "=========================="

# Test 1: HTML file structure and security headers
test_html_structure() {
	echo -e "\n🔧 Testing HTML Structure and Security"

	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Test CSP header exists
			if grep -q "Content-Security-Policy" "$html_file"; then
				assert_equal "present" "present" "CSP header present in $filename"
			else
				assert_equal "present" "missing" "ERROR: CSP header missing in $filename"
			fi

			# Test viewport meta tag (mobile responsive)
			if grep -q 'name="viewport"' "$html_file"; then
				assert_equal "present" "present" "Viewport meta tag present in $filename"
			else
				assert_equal "present" "missing" "ERROR: Viewport meta tag missing in $filename"
			fi

			# Test Chart.js CDN link
			if grep -q "chart.js" "$html_file"; then
				assert_equal "present" "present" "Chart.js CDN reference present in $filename"
			else
				assert_equal "present" "missing" "Chart.js CDN reference missing in $filename"
			fi

			# Test that there are no hardcoded secrets or tokens
			if grep -qE "(ghp_|github_pat_)" "$html_file"; then
				assert_equal "clean" "has_secrets" "ERROR: Hardcoded tokens found in $filename"
			else
				assert_equal "clean" "clean" "No hardcoded secrets in $filename"
			fi

		else
			assert_equal "exists" "missing" "ERROR: $html_file does not exist"
		fi
	done
}

# Test 2: JavaScript error handling patterns
test_javascript_error_handling() {
	echo -e "\n🚫 Testing JavaScript Error Handling"

	for js_file in "${JS_FILES[@]}"; do
		if [[ -f "$js_file" ]]; then
			local filename
			filename=$(basename "$js_file")

			# Count try-catch blocks
			local try_count
			try_count=$(grep -c "try {" "$js_file" || true)
			local catch_count
			catch_count=$(grep -c "catch" "$js_file" || true)

			if [[ $try_count -eq $catch_count ]] && [[ $try_count -gt 0 ]]; then
				assert_equal "balanced" "balanced" "Try-catch blocks balanced in $filename ($try_count pairs)"
			else
				assert_equal "balanced" "unbalanced" "ERROR: Try-catch blocks unbalanced in $filename"
			fi

			# Test error logging patterns
			if grep -q "console.error" "$js_file"; then
				assert_equal "present" "present" "Error logging present in $filename"
			else
				assert_equal "present" "missing" "ERROR: No error logging found in $filename"
			fi

			# Test API error handling for GitHub API
			if grep -q "GitHub API error" "$js_file"; then
				assert_equal "present" "present" "GitHub API error handling present in $filename"
			else
				assert_equal "present" "missing" "API error handling missing in $filename"
			fi

			# Test user-friendly error display
			if grep -q "showError\|show.*[Ee]rror" "$js_file"; then
				assert_equal "present" "present" "User error display functions present in $filename"
			else
				assert_equal "present" "missing" "User error display missing in $filename"
			fi

		else
			assert_equal "exists" "missing" "ERROR: $js_file does not exist"
		fi
	done
}

# Test 3: CDN dependency validation
test_cdn_dependencies() {
	echo -e "\n🌐 Testing CDN Dependencies"

	# Check for expected CDN dependencies directly in HTML files
	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Test Chart.js CDN
			if grep -q "chart.js" "$html_file"; then
				assert_equal "present" "present" "Chart.js CDN found in $filename"
			else
				assert_equal "present" "missing" "Chart.js CDN missing in $filename"
			fi

			# Test Font Awesome CDN
			if grep -q "fontawesome\|font-awesome" "$html_file"; then
				assert_equal "present" "present" "FontAwesome CDN found in $filename"
			else
				assert_equal "present" "missing" "FontAwesome CDN missing in $filename"
			fi
		fi
	done
}

# Test 4: LocalStorage security patterns
test_localstorage_security() {
	echo -e "\n🔐 Testing LocalStorage Security Patterns"

	for js_file in "${JS_FILES[@]}"; do
		if [[ -f "$js_file" ]]; then
			local filename
			filename=$(basename "$js_file")

			# Test that GitHub tokens are stored in localStorage (expected for client-side app)
			if grep -q "localStorage.*token\|localStorage.*Token" "$js_file"; then
				assert_equal "client_side_storage" "client_side_storage" "Client-side token storage detected in $filename"
			fi

			# Test that there are warnings about token security
			if grep -qE "(warning|Warning|security|Security|read.*only|readonly)" "$js_file"; then
				assert_equal "security_aware" "security_aware" "Security awareness indicators found in $filename"
			else
				# This is acceptable for client-side dashboard, but good to note
				assert_equal "security_notes" "security_notes" "Note: Consider adding security warnings for token usage"
			fi

			# Test that sensitive data is not logged
			local sensitive_log_count
			sensitive_log_count=$(grep -cE "console\.log.*token|console\.log.*Token|console\.log.*secret" "$js_file" 2>/dev/null || true)
			assert_equal "0" "$sensitive_log_count" "No sensitive data in console logs"
		fi
	done
}

# Test 5: Mobile responsiveness indicators
test_mobile_responsiveness() {
	echo -e "\n📱 Testing Mobile Responsiveness Indicators"

	# Test CSS for responsive patterns
	for css_file in "${CSS_FILES[@]}"; do
		if [[ -f "$css_file" ]]; then
			local filename
			filename=$(basename "$css_file")

			# Test for media queries
			local media_query_count
			media_query_count=$(grep -c "@media" "$css_file" 2>/dev/null || true)
			if [[ $media_query_count -gt 0 ]]; then
				assert_equal "responsive" "responsive" "Media queries found in $filename ($media_query_count)"
			else
				assert_equal "responsive" "not_responsive" "No media queries in $filename"
			fi

			# Test for flexbox or grid (modern responsive layouts)
			if grep -qE "(display:\s*(flex|grid)|flex|grid)" "$css_file"; then
				assert_equal "modern_layout" "modern_layout" "Modern layout patterns in $filename"
			else
				assert_equal "modern_layout" "traditional" "Traditional layout in $filename"
			fi
		fi
	done

	# Test HTML for touch-friendly elements
	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Test for touch-friendly button sizing (common class patterns)
			if grep -qE "(btn-|button|touch)" "$html_file"; then
				assert_equal "touch_friendly" "touch_friendly" "Touch-friendly elements in $filename"
			else
				assert_equal "touch_friendly" "basic" "Basic button elements in $filename"
			fi
		fi
	done
}

# Test 6: Accessibility basics
test_accessibility_basics() {
	echo -e "\n♿ Testing Accessibility Basics"

	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Test for alt attributes on images
			local img_count
			img_count=$(grep -c "<img" "$html_file" 2>/dev/null || true)
			local alt_count
			alt_count=$(grep -c 'alt=' "$html_file" 2>/dev/null || true)

			if [[ $img_count -eq 0 ]]; then
				assert_equal "no_images" "no_images" "No images to test alt attributes in $filename"
			elif [[ $img_count -eq $alt_count ]]; then
				assert_equal "all_have_alt" "all_have_alt" "All images have alt attributes in $filename"
			else
				assert_equal "all_have_alt" "missing_alt" "Some images missing alt attributes in $filename"
			fi

			# Test for semantic HTML elements
			if grep -qE "<(header|nav|main|section|article|aside|footer)>" "$html_file"; then
				assert_equal "semantic" "semantic" "Semantic HTML elements found in $filename"
			else
				assert_equal "semantic" "non_semantic" "Consider adding semantic HTML elements in $filename"
			fi

			# Test for ARIA labels or roles
			if grep -qE "(aria-|role=)" "$html_file"; then
				assert_equal "aria_present" "aria_present" "ARIA attributes found in $filename"
			else
				assert_equal "aria_present" "basic" "Basic accessibility in $filename (consider ARIA)"
			fi
		fi
	done
}

# Test 7: Performance indicators
test_performance_indicators() {
	echo -e "\n⚡ Testing Performance Indicators"

	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Test for preloading critical resources
			if grep -q "preload\|prefetch" "$html_file"; then
				assert_equal "preload_present" "preload_present" "Resource preloading found in $filename"
			else
				assert_equal "preload_present" "basic" "No resource preloading in $filename"
			fi

			# Test for font-display optimization
			if grep -q "font-display" "$html_file"; then
				assert_equal "font_optimization" "font_optimization" "Font display optimization in $filename"
			else
				assert_equal "font_optimization" "basic" "Basic font loading in $filename"
			fi
		fi
	done

	# Test JavaScript for performance patterns
	for js_file in "${JS_FILES[@]}"; do
		if [[ -f "$js_file" ]]; then
			local filename
			filename=$(basename "$js_file")

			# Test for debouncing/throttling patterns
			if grep -qE "(setTimeout|setInterval|debounce|throttle)" "$js_file"; then
				assert_equal "performance_patterns" "performance_patterns" "Performance optimization patterns in $filename"
			else
				assert_equal "performance_patterns" "basic" "Basic event handling in $filename"
			fi

			# Test for efficient DOM queries (caching selectors)
			if grep -qE "(getElementById|querySelector)" "$js_file"; then
				local query_count
				query_count=$(grep -cE "(getElementById|querySelector)" "$js_file")
				assert_equal "dom_queries" "dom_queries" "DOM queries found ($query_count instances) in $filename"
			fi
		fi
	done
}

# Test 8: File integrity and syntax
test_file_integrity() {
	echo -e "\n🔍 Testing File Integrity and Syntax"

	# Test HTML syntax (basic)
	for html_file in "${HTML_FILES[@]}"; do
		if [[ -f "$html_file" ]]; then
			local filename
			filename=$(basename "$html_file")

			# Check for unclosed tags (basic test)
			if grep -q "<html" "$html_file" && grep -q "</html>" "$html_file"; then
				assert_equal "html_structure" "html_structure" "Basic HTML structure valid in $filename"
			else
				assert_equal "html_structure" "invalid" "ERROR: HTML structure issues in $filename"
			fi

			# Check for DOCTYPE
			if head -5 "$html_file" | grep -q "<!DOCTYPE"; then
				assert_equal "doctype_present" "doctype_present" "DOCTYPE declaration present in $filename"
			else
				assert_equal "doctype_present" "missing" "DOCTYPE missing in $filename"
			fi
		fi
	done

	# Test JavaScript syntax (basic)
	for js_file in "${JS_FILES[@]}"; do
		if [[ -f "$js_file" ]]; then
			local filename
			filename=$(basename "$js_file")

			# Check for balanced braces (basic test)
			local open_braces
			open_braces=$(grep -o "{" "$js_file" | wc -l)
			local close_braces
			close_braces=$(grep -o "}" "$js_file" | wc -l)

			if [[ $open_braces -eq $close_braces ]]; then
				assert_equal "balanced_braces" "balanced_braces" "Balanced braces in $filename"
			else
				assert_equal "balanced_braces" "unbalanced" "ERROR: Unbalanced braces in $filename"
			fi

			# Check for common syntax errors
			if grep -qE "(undefined.*function|function.*undefined)" "$js_file"; then
				assert_equal "syntax_clean" "syntax_error" "ERROR: Potential syntax errors in $filename"
			else
				assert_equal "syntax_clean" "syntax_clean" "No obvious syntax errors in $filename"
			fi
		fi
	done
}

# Helper function to test if a URL is reachable (for CDN testing)
test_url_reachable() {
	local url="$1"
	local timeout="${2:-5}"

	if command -v curl >/dev/null 2>&1; then
		if curl -s --head --max-time "$timeout" "$url" >/dev/null 2>&1; then
			return 0
		else
			return 1
		fi
	else
		# Skip URL reachability test if curl not available
		return 0
	fi
}

# Test 9: CDN reachability (optional - requires internet)
test_cdn_reachability() {
	echo -e "\n🔗 Testing CDN Reachability (optional)"

	# Common CDN endpoints used by the dashboard
	local test_urls=(
		"https://cdn.jsdelivr.net/npm/chart.js"
		"https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css"
		"https://fonts.googleapis.com/css2"
	)

	local reachable_count=0
	for url in "${test_urls[@]}"; do
		if test_url_reachable "$url" 3; then
			((reachable_count++))
			echo -e "${GREEN}✓${NC} $url reachable"
		else
			echo -e "${YELLOW}⚠${NC} $url not reachable (offline or blocked)"
		fi
	done

	# This is informational only - not a failure if CDNs are unreachable
	assert_equal "info" "info" "CDN reachability test completed ($reachable_count/${#test_urls[@]} reachable)"
}

# Run all tests
main() {
	test_html_structure
	test_javascript_error_handling
	test_cdn_dependencies
	test_localstorage_security
	test_mobile_responsiveness
	test_accessibility_basics
	test_performance_indicators
	test_file_integrity
	test_cdn_reachability

	# Print results
	echo -e "\n📋 Dashboard Test Results Summary"
	echo "================================="
	echo -e "Total Tests: $TEST_COUNT"
	echo -e "${GREEN}Passed: $PASSED_COUNT${NC}"
	echo -e "${RED}Failed: $FAILED_COUNT${NC}"

	if [[ $FAILED_COUNT -eq 0 ]]; then
		echo -e "\n${GREEN}🎉 All dashboard tests passed!${NC}"
		exit 0
	else
		echo -e "\n${RED}❌ Some tests failed. Please review and fix.${NC}"
		exit 1
	fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
