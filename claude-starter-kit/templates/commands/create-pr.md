---
description: Mandatory path for creating a PR or pushing a fix to an open PR branch — verify locally first, then monitor CI until green.
argument-hint: [repo] [context]
---

# Create PR

Target: $ARGUMENTS

A PR is NOT done when it's opened — it's done when CI is green.

## Steps

1. **Context.** Identify which sibling repo the change lives in; load its skill
   (`.claude/skills/<slug>/SKILL.md`). Work in the real repo clone, never in a
   reference copy inside the orchestrator.
2. **Branch.** Never commit to `main`. If on `main`, create
   `feat|fix|chore/<short-description>` first.
3. **Verify locally.** Run the build + tests from the skill's Quick Commands. A red
   local build never becomes a PR. Record what you ran and the result for the PR body.
4. **Review the diff.** `git diff` — every changed line must trace to the request; drop
   unrelated/accidental changes (formatting sweeps, lockfiles you didn't mean to touch).
5. **Push + open the PR.** Target `main` unless the repo's skill says otherwise. Body:
   **What** changed, **Why**, **How tested** (exact commands + results — never claim
   something was tested if it wasn't). Link the ticket if there is one.
6. **Monitor CI until green.** Poll the PR checks (e.g. `gh pr checks <n> --watch`).
   - Red check caused by your change → fix it, push to the same branch, back to step 3.
   - Red check pre-existing/unrelated → prove it (e.g. link the same failure on `main`)
     and note it in a PR comment.
   Only report "PR ready" when checks are green or every red is proven unrelated.

Updating an existing PR (pushing a fix) follows the same steps from 3.
