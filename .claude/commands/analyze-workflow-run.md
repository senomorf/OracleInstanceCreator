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

First, read project CLAUDE.md instructions.
Then, thinking deep analyze this workflow run.
Then, $2
