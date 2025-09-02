---
allowed-tools: Bash(git remote:*), Bash(git branch:*), Bash(git status:*)
description: Get repository details
model: claude-sonnet-4-20250514
---

## Context

- GitHub Repository: !`git remote get-url origin | sed 's/^.*://;s/.git$//'`
- Current branch: !`git branch --show-current`
- Current git status: !`git status`

## Your task

Provide repository brief:
- remote repository
- remote repository owner username
- remote repository name
- current branch
- current branch status