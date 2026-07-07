# dmoney-tracker orchestrator

Central "AI operations brain" for the dmoney-tracker system. Contains **no product
code** — skills, routing and tooling that let an AI coding agent (Claude Code, etc.)
understand the whole system. See `HOW-TO-BUILD-AN-ORCHESTRATOR.md` for the model.

## Layout

The three repos are **siblings** in the parent directory:

```
dmoney-tracker/
├── dmoney-tracker-be/            # .NET 10 API (source of truth: its CLAUDE.md)
├── dmoney-tracker-web/           # Vite + React + Tailwind + shadcn/ui frontend
└── dmoney-tracker-orchestrator/  # ← this repo
```

## Quick start

```bash
make clone-all              # clone missing sibling repos (idempotent)
make status                 # git status of every repo
docker compose up --build   # full stack: postgres :5432, api :5113, web :8080
```

## How the AI brain works

- `CLAUDE.md` — thin global rules for Claude Code (every session).
- `AGENTS.md` — same contract for any other agent (Copilot/Codex/Cursor).
- `.claude/skills/` — one skill per service + one platform-wide map:
  `dmoney-platform` (bird's-eye), `dmoney-backend`, `dmoney-web`.
- `agent_docs/skill-routing.md` — topic→skill and directory→skill tables.

Golden rule: code changes happen in the real repos (`../dmoney-tracker-be`,
`../dmoney-tracker-web`), never treat this repo as the place to edit product code.
