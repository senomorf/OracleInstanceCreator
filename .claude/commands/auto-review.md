# Auto-Review Command

REPO: $1
PR NUMBER: $2

Perform a comprehensive code review for the OCI automation project covering both general software engineering principles and OCI automation specifics.

## Review Areas

### 1. Code Quality
- Clean code principles and best practices
- Proper error handling and input validation
- Code structure, readability, and maintainability
- Logic bugs, edge cases, and null checks
- Algorithm efficiency and resource usage
- Check for race conditions and concurrency issues
- Configuration and environment dependencies
- Documentation quality and code comments
- Adherence to coding standards and conventions
- Verify that README.md and docs are updated for any new features or config changes
- **Linter Policy Compliance**: Ensure any new linters focus on code quality/security/functional issues, NOT arbitrary style rules

### 2. Security
- Check for potential security vulnerabilities
- Validate input sanitization
- Review authentication/authorization logic
- **Credential Safety**: Check for exposed credentials (OCI OCIDs, keys, SSH keys, tokens)

### 3. Performance
- Algorithm complexity and optimization opportunities
- Identify potential performance bottlenecks
- Review database queries for efficiency
- Check for memory leaks or resource issues
- Workflows use caching and optimized for run time

### 4. Testing
- Verify adequate test coverage
- Review test quality and edge cases
- Check for missing test scenarios
- All PR workflows with checks, linters pass successfully

### 5. Documentation
- Ensure code is properly documented
- Verify README updates for new features
- Check API documentation accuracy

### 6. OCI-Specific Automation Patterns
- Verify capacity errors return 0 (expected) vs 1 (real failure)
- OCI CLI optimization to minimize Oracle API calls
- Optimal connect/receive timeouts
- PR workflows using OCI must be passing (assume credentials and configurations and valid)
- Distinguish capacity issues from real failures

## Review Process

Be constructive, thorough, and provide specific actionable feedback.
Provide severity ratings (Critical/High/Medium/Low) for any issues found.
Medium, High and Critical severity issues must be addressed before merging the PR.
Low severity issues should be either addressed before merging the PR or GitHub issues must be created for each issue found in review.

Note: The PR branch is already checked out in the current working directory.

Only post GitHub comment - don't submit review text as messages.
Submit review as an update of your previous review PR comment if it exists.
Post review create new review comment or updating existing review comment, for example:
`gh pr comment $2 --edit-last --create-if-none --body "your review"`.

Additionally leave top-level feedback of your review using `gh pr review` command, providing link to review comment.
Do one of the following:
- approve if there are no issues, providing a link to the PR comment for more details, for example:
  `gh pr review $2 --approve --body "Looks good, but consider adding more tests. See <REVIEW COMMENT URL> PR comment for details."`
- request changes if there are issues of medium priority or higher, providing a link to the PR comment for more details, for example:
  `gh pr review $2 --request-changes --body "Needs changes to address performance issues. See <REVIEW COMMENT URL> PR comment for details."`
