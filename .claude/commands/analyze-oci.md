---
allowed-tools: Bash, mcp__gh, mcp__github, mcp__github_ci
argument-hint: [prompt]
description: Analyze latest OCI workflow run
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- WORKFLOW_FILE_NAME: infrastructure-deployment.yml
- WORKFLOW_RUN_ID: !`gh run list --workflow $WORKFLOW_FILE_NAME --limit 1 --json databaseId --jq '.[0].databaseId' | awk '{print($0)}' | column`
- Workflow run details: !`gh run view $WORKFLOW_RUN_ID --json conclusion,status,databaseId,workflowDatabaseId,workflowName,headBranch,jobs`
- Complete log of Core OCI workflow step 'Launch OCI Instances (Parallel)': 
  !`gh run view $WORKFLOW_RUN_ID --log | grep 'Launch OCI Instances (Parallel)' |  awk '{ sub(/^.*Z/,""); print }'`
- Log of only failed jobs:
  !`gh run view $WORKFLOW_RUN_ID --log-failed | awk '{ sub(/^.*Z/,""); print }'`
- Workflow file: @.github/workflows/$WORKFLOW_FILE_NAME

## Your task

This workflow shouldn't have failed under ANY circumstances. Credentials are valid, and the workflow is configured correctly.
Thinking deep analyze this workflow run.
Now, $1
