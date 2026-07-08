# Skill routing & platform reference (__PROJECT__)

Referenced, not auto-loaded. Always load the matching `.claude/skills/<name>/SKILL.md`
before responding on its topic. Whole-system map: the `platform` skill.

## Directory -> skill (path-based)

| Working directory | Skill |
|---|---|
__ROWS:dir-skill__

## Topic -> skill (keyword-based)

| User says... | Skill |
|---|---|
| architecture, system overview, which service | `platform` |
| (add keyword rows: e.g. "database, query, migration" -> a skill) | |

## Workflow commands

| Task | Command |
|---|---|
| Create or update a PR (verify locally, monitor CI) | `/create-pr` |
| Review a PR | `/pr-review` |
| Search across all repos | `/cross-repo-search` |
| Uncommitted work / branch overview | `/status-check` |
| Auto-draft a service skill from its repo | `/populate-skill` |

## Repositories

__ROWS:repo-list__
