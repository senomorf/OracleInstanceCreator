---
allowed-tools: Bash(git remote:*), Bash(gh run view:*)
argument-hint: [workflow run id] [prompt]
description: Analyze specific OCI workflow run
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- Workflow run details: !`gh run view $1 --json conclusion,status,databaseId,workflowDatabaseId,workflowName,headBranch,jobs`
- Complete log of Core OCI workflow step 'Launch OCI Instances (Parallel)': 
  !`gh run view $1 --log | grep 'Launch OCI Instances (Parallel)' |  awk '{ sub(/^.*Z/,""); print }'`
- Log of only failed jobs:
  !`gh run view $1 --log-failed | awk '{ sub(/^.*Z/,""); print }'`
- Workflow file: @.github/workflows/infrastructure-deployment.yml

## Your task

Perform specialized OCI workflow analysis focusing on:

**CRITICAL PATTERNS TO VALIDATE**:
- Performance benchmarks: <20s optimal, 20-30s acceptable, >30s investigate  
- OCI CLI optimization flags: --no-retry, --connection-timeout 5, --read-timeout 15
- Parallel execution: A1.Flex (4 OCPUs, 24GB) + E2.1.Micro (1 OCPU, 1GB)
- Error classification: CAPACITY/DUPLICATE (success), TRANSIENT (retry), AUTH/CONFIG (alert)
- Circuit breaker behavior: 3 AD failures = skip

**ANALYSIS REQUIREMENTS**:
1. **Read CLAUDE.md** first for project-specific patterns and benchmarks
2. **Parse parallel execution logs** for environment variable injection validation
3. **Classify errors** according to documented patterns (capacity vs transient vs config)
4. **Validate notification policy** compliance (notify on success/critical, silent on capacity)
5. **Cross-reference git changes** that might affect workflow behavior

**OUTPUT STRUCTURE**:
- **Performance Analysis**: Timing vs benchmarks, parallel efficiency
- **Error Classification**: Pattern matching against CLAUDE.md specifications  
- **Configuration Validation**: OCI CLI flags, environment variables, proxy settings
- **Root Cause**: Specific failure analysis with actionable fixes
- **Recommendations**: CLAUDE.md-compliant solutions with implementation steps

Note that this OCI workflow shouldn't have completed with failure status. Credentials are valid, and the workflow is configured correctly.

Now, $2
