---
description: Search a pattern across every cloned sibling repo and report hits grouped by repository.
argument-hint: <pattern>
---

# Cross-Repo Search

Pattern: $ARGUMENTS

1. Enumerate the repos (`make list`, or `PRIMARY_REPOS` in the Makefile).
2. Search each clone (ripgrep) for the pattern — code, config, and docs.
3. Report `repo/path:line` hits grouped by repository, with a 1-line interpretation
   per repo.
4. Explicitly list repos with ZERO matches so coverage is provable.
5. Repos not cloned yet: say so (`make clone-all` to fetch) rather than silently skipping.
