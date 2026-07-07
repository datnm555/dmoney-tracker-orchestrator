---
description: Create a pull request for the current feature branch of a dmoney-tracker repo
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
4. Create the PR with `gh pr create` against `main`:
   - Title: conventional-commit style summary of the branch's work.
   - Body: `## Summary` (what & why, bullet list from the branch's commits),
     `## Test plan` (the gate commands run and their results), plus any extra
     context from `$ARGUMENTS`.
   - End the body with: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
5. Print the PR URL.

Cross-repo note: if the branch changes a cross-repo contract (DTO shapes,
category/payment codes, resx keys — see the `dmoney-platform` skill), mention the
sibling-repo PR/branch in the body so reviewers can pair them.
