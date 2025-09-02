---
allowed-tools: Bash(git remote:*), Bash(gh run view:*)
argument-hint: [workflow run id] [prompt]
description: Analyze specific workflow run
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- Workflow run details: !`gh run view $1 --json conclusion,status,databaseId,workflowDatabaseId,workflowName,headBranch,jobs`
- Log of failed jobs:
  !`gh run view $1 --log-failed | awk '{ sub(/^.*Z/,""); print }'`

## Your task

Perform general GitHub Actions workflow analysis focusing on:

**ANALYSIS AREAS**:
- **Job-level failures**: Identify specific jobs and steps that failed
- **GitHub Actions best practices**: Validate workflow structure and patterns
- **Dependency issues**: Check for missing dependencies, environment setup failures
- **Configuration drift**: Compare against successful runs and expected patterns
- **Resource utilization**: Analyze timing, resource usage, and efficiency

**ANALYSIS REQUIREMENTS**:
1. **Read CLAUDE.md** first for any project-specific workflow patterns
2. **Parse failed job logs** for specific error messages and failure points
3. **Cross-reference git changes** that might have introduced workflow issues
4. **Identify failure patterns**: Recurring vs one-time failures, environmental vs code issues
5. **Validate workflow file structure** for GitHub Actions best practices

**OUTPUT STRUCTURE**:
- **Execution Summary**: Overall workflow status, duration, and failure points
- **Job Analysis**: Detailed breakdown of failed jobs with specific error messages
- **Root Cause**: Primary failure cause with supporting evidence from logs
- **Git History Impact**: Recent changes that may have affected workflow behavior
- **Fix Plan**: Specific, actionable steps to resolve identified issues

Now, $2
