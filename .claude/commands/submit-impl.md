---
allowed-tools: Bash, mcp__gh, mcp__github, mcp__github_ci
description: Submit implementation to GitHub
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Fetch from remote; then create new branch; then commit uncommitted changes; then verify that new branch is clean (contains no unrelated commits from other branches besides master), drop them if there are, keeping changes in new branch focused around specific implementation; then rebase on master, resolving conflicts; then push; then create PR.
