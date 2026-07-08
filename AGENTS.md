# AGENTS.md

Shared agent contract for the dmoney-tracker orchestrator (Codex, Cursor, Aider —
Claude Code reads CLAUDE.md, same rules).

- Skills (single source of truth) live in `.claude/skills/<name>/SKILL.md`.
  When any doc mentions `/skill-name`, read that skill file BEFORE answering or acting.
- Routing (topic→skill, directory→skill): `agent_docs/skill-routing.md`.
- This repo holds no product code. Make code changes in the sibling repos
  `../dmoney-tracker-be` and `../dmoney-tracker-web`; each has its own CLAUDE.md
  with authoritative per-repo conventions.
- Workflow changes belong in the skill body so every tool stays in sync — do not
  fork tool-specific copies of skill content.
- Git flow (branching, agent commit/push authorization): see the "Git flow"
  section in `CLAUDE.md` — the same rules apply to every agent.
