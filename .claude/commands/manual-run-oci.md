---
allowed-tools: Bash, mcp__gh, mcp__github, mcp__github_ci
description: Run main OCI workflow, wait for completion, process results
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`

!`gh workflow run infrastructure-deployment.yml --ref $(git branch --show-current) -f check_existing_instance=false -f adaptive_scheduling=false -f region_optimization=false`

- Workflow run id: !`gh run list --workflow infrastructure-deployment.yml --branch $(git branch --show-current) --limit 1 --json databaseId --jq '.[0].databaseId' | awk '{print($0)}' | column`

## Your task

First, read project CLAUDE.md instructions.
Then wait for workflow to complete, watching its progress.
Then analyze results and report summary.
