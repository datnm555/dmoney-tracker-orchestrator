---
description: Report working-tree state across all cloned repos — uncommitted changes, current branches, unpushed work.
---

# Status Check

1. `make status` — repos with uncommitted changes (show the short status per repo).
2. `make branches` — current branch per repo; flag any repo sitting on `main` with
   local changes.
3. For dirty repos with an upstream: `git log --oneline @{u}..` (unpushed commits).
4. Summarize: clean repos (count), dirty repos (each: branch + what's pending), and
   missing clones.
