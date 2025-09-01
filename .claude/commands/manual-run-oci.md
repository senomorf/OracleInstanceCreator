---
allowed-tools: Bash, mcp__gh, mcp__github, mcp__github_ci
description: Run main OCI workflow, wait for completion, process results
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- CURRENT_BRANCH: !`git branch --show-current`
- WORKFLOW_FILE_NAME: infrastructure-deployment.yml
!`gh workflow run $WORKFLOW_FILE_NAME --ref $CURRENT_BRANCH -f check_existing_instance=false -f adaptive_scheduling=false -f region_optimization=false`
- Workflow run id: !`gh run list --workflow $WORKFLOW_FILE_NAME --branch $CURRENT_BRANCH --limit 1 --json databaseId --jq '.[0].databaseId' | awk '{print($0)}' | column`

## Your task

Read project CLAUDE.md instructions.
Wait for workflow to complete, watching its progress.
Now analyze results and report summary.
