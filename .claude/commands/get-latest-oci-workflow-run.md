---
allowed-tools: Bash(git remote:*), Bash(gh run list:*)
description: Get latest scheduled OCI workflow run
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- OCI Workflow file name: `infrastructure-deployment.yml`
- Latest scheduled OCI workflow run ID: !`gh run list --event schedule --workflow infrastructure-deployment.yml --branch master --limit 1 --json databaseId --jq '.[0].databaseId' | awk '{print($0)}' | column`

## Your task

Provide VERY brief summary of your context including workflow run ID.
