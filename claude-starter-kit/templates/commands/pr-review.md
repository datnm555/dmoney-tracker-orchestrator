---
description: Review a pull request against the owning service's skill — correctness, tests, conventions, security.
argument-hint: <pr-number-or-url>
---

# PR Review

Target: $ARGUMENTS

1. **Load context.** Fetch the PR (description + full diff). Identify the repo; load its
   skill — review against ITS conventions, not generic taste.
2. **Correctness first.** Trace the changed logic; hunt for bugs, broken edge cases, and
   behaviour changes not covered by the description.
3. **Tests.** Does the diff include/update tests per the skill's "How to Test"? Would
   the tests fail without the change?
4. **Conventions & scope.** Naming/pattern rules from the skill; flag unrelated changes
   that snuck into the diff.
5. **Security & safety.** Secrets in the diff, injection, authz gaps, unsafe migrations,
   destructive operations without a guard.
6. **Report.** Findings ordered by severity, each with `file:line` + a concrete
   suggestion. Verdict: approve / request changes. Don't invent nitpicks to seem thorough.
