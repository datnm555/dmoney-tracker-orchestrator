# __PROJECT__ Orchestrator — Claude Code Instructions

Central orchestrator for all __PROJECT__ repositories. Holds **AI config only** —
skills, commands, this file — **not application code**. Real repos are cloned as
siblings (`make clone-all`) for read-only reference; make all code changes/commits/PRs
in the real repo clones.

## How to work here
1. Think before coding; state assumptions; ask when ambiguous.
2. Simplicity first; surgical changes only.
3. Turn vague asks into verifiable success criteria; verify before claiming done.

## Skill system
Each service/domain is a skill at `.claude/skills/<name>/SKILL.md`; the whole-system
map is the `platform` skill. The routing contract (topic→skill, directory→skill) is
`agent_docs/skill-routing.md`. **Always load the matching skill BEFORE responding** on
its topic — don't answer from general knowledge.

Workflow commands in `.claude/commands/`:
- `/create-pr` — the mandatory path for opening/updating a PR (verify locally, monitor CI until green).
- `/pr-review` — review a PR against the owning service's skill.
- `/cross-repo-search` — search a pattern across every cloned repo.
- `/status-check` — uncommitted work / branch overview across repos.
- `/populate-skill` — auto-draft a service skill by reading its actual repo clone.

## Repository locations
- Orchestrator (this dir): skills + read-only reference clones.
- Working repos: the real sibling clones — change code there. PRs target `main`.

## Production safety
Read-only by default. Mutating cloud/DB/infra calls require explicit permission and a
verified account/region. Never DROP/DELETE/destroy without confirmation.
