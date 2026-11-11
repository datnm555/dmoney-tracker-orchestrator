---
description: Gate-check, push, open + merge the PR, and deploy the current feature branch of a dmoney-tracker repo
argument-hint: [be|web|orchestrator] [optional extra context for the PR body]
---

Create a pull request for the dmoney-tracker repo the user names in `$ARGUMENTS`
(`be` → `../dmoney-tracker-be`, `web` → `../dmoney-tracker-web`, `orchestrator` →
this repo). If no repo is named, use the repo of the current working directory;
if that is ambiguous, ask.

Steps:

1. In the target repo, confirm the current branch is NOT `main` and is clean
   (`git status -sb`). If on `main`, stop and tell the user a feature branch is
   required first.
2. Run the repo's gates before opening the PR:
   - be: `dotnet build DMoney.slnx` (zero warnings) + `dotnet test tests/Application.UnitTests`
   - web: `npm run build && npm test`
   - orchestrator: no build gate (docs/config only)
   If a gate fails, stop and report — never open a PR on a red build.
3. Push the branch: `git push -u origin <branch>` (agent is authorized to push —
   see CLAUDE.md "Git flow").
4. Create the PR against `main` with the MCP `github` tools
   (`mcp__github__create_pull_request`, owner `datnm555`) — NOT `gh`, which is
   logged into a different account:
   - Title: conventional-commit style summary of the branch's work.
   - Body: `## Summary` (what & why, bullet list from the branch's commits),
     `## Test plan` (the gate commands run and their results), plus any extra
     context from `$ARGUMENTS`.
   - End the body with: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
5. Merge it right away (`mcp__github__merge_pull_request`, merge method `merge`)
   — the owner authorized auto-merge (CLAUDE.md "Ship flow"). For cross-repo
   contract changes merge the be PR before the web PR.
6. Deploy (be/web only): `git checkout main && git pull` in the repo, then
   `docker compose build <api|web>` in the background and
   `docker compose up -d <api|web>` from this repo; verify :5113 / :8080.
7. Print the PR URL(s) and the deploy result. If merge or deploy fails, stop and
   report instead of working around it.

Cross-repo note: if the branch changes a cross-repo contract (DTO shapes,
category/payment codes, resx keys — see the `dmoney-platform` skill), mention the
sibling-repo PR/branch in the body so reviewers can pair them.
