# Claude Starter Kit — carry this model to another project

A **portable** kit for standing up a **Claude Code** orchestrator for **any** multi-repo /
multi-service project. Philosophy: **one source of truth** — each service is packaged as one
`.claude/skills/<svc>/SKILL.md` the agent loads at the right moment. Full theory:
[HOW-TO-BUILD-AN-ORCHESTRATOR-claude-en.md](HOW-TO-BUILD-AN-ORCHESTRATOR-claude-en.md).

## Quick start (one command)

Copy the **whole `claude-starter-kit/` directory** (the script needs `templates/`
next to it), then:

```bash
PROJECT_NAME="Acme" \
GIT_ORG="acme-inc" \
REPOS="api web worker other-org/infra" \
TARGET_DIR=./acme-orchestrator \
./bootstrap.sh
```

Each `REPOS` entry is either `repo` (cloned from `GIT_ORG`) or `org/repo` (explicit org —
multi-org projects work out of the box). The script scaffolds in `TARGET_DIR`:

```
acme-orchestrator/
├── CLAUDE.md                         # global rules for Claude Code (thin — loads every session)
├── .gitignore                        # ignores reference clones + .mcp.json/local config
├── .claude/
│   ├── skills/
│   │   ├── platform/SKILL.md          # ★ whole-system map skeleton (fill the repo table)
│   │   └── <repo>/SKILL.md            # ★ 1 skill per repo (source of truth)
│   └── commands/                      # ★ generic workflow commands (pre-generated):
│       ├── create-pr.md               #   mandatory PR path + CI monitoring
│       ├── pr-review.md               #   review a PR against the service's skill
│       ├── cross-repo-search.md       #   search a pattern across every repo
│       ├── status-check.md            #   branch/uncommitted overview
│       └── populate-skill.md          #   ★ AI auto-drafts SKILL.md by reading the repo
├── agent_docs/skill-routing.md        # topic→skill, dir→skill, workflow-command tables
├── Makefile                           # clone-all / pull-all / status / branches / doctor
└── .orchestrator-kit-version          # kit version this was scaffolded from (see VERSION)
```

**Idempotent:** re-run as often as you like. Existing files (skills you've filled in) are
**kept**; new repos in `REPOS` get their skill generated — but add the repo to the Makefile
`PRIMARY_REPOS`, the routing tables, and `.gitignore` yourself (`make doctor` reminds you if
you forget).

## After running the script — 4 things to do

1. `cd <TARGET_DIR> && make clone-all` — pull the real repos as siblings (read-only ref).
2. **Open Claude Code and run `/populate-skill <repo>`** (or `all`) — the AI reads the
   actual clone (README, build files, CI, directory structure) and drafts each SKILL.md.
   You **review** instead of writing from scratch. (No Claude Code? Fill the template by hand.)
3. Fill the repo table + service relationships in `.claude/skills/platform/SKILL.md`, and
   add **topic→skill** keyword rows to `agent_docs/skill-routing.md`.
4. `make doctor` — validates the structure (missing skills / routing / `.gitignore`) and
   lists skills still on placeholders. Repeat until it's clean.

## Doing it by hand (without the script)

Minimal checklist to carry the model:

- [ ] Create an empty orchestrator repo (NO product code).
- [ ] `.gitignore` ignoring the reference-clone directories + `.mcp.json`/local config
      (so `make clone-all` can't accidentally commit product code into the orchestrator).
- [ ] Thin `CLAUDE.md`.
- [ ] `Makefile` with `clone-all/pull-all/status/branches/doctor` from the repo list.
- [ ] Each service → `.claude/skills/<svc>/SKILL.md` (trigger-rich frontmatter).
- [ ] `agent_docs/skill-routing.md`: dir→skill + topic→skill tables.
- [ ] One `platform` skill as the whole-system map.
- [ ] Workflow commands in `.claude/commands/` (take them from `templates/commands/`).

## Decisions when porting to a new project

| Question | Guidance |
|---|---|
| 1 repo = 1 skill, or merge? | Large/standalone service → own skill. Small same-family group → one merged skill (e.g. 4 microservices). |
| Where does a fact live? | How-to/commands → skill. Team knowledge (architecture, runbooks) → vault/docs. Personal state → memory (gitignored). Never duplicate. |
| Change generated file content? | Edit the kit's `templates/` (the script holds logic only — no embedded bodies). |
| Also running Codex / Cursor? | Keep `.claude/skills/` as the source; add a thin adapter (`AGENTS.md` + a `.agents/skills → .claude/skills` symlink) that points back. Not scaffolded by this Claude-only kit. See HOW-TO §11. |

## Invariants (don't break these)

- The orchestrator holds **no product code** — reference clones only; change code in the real repos.
- `CLAUDE.md` stays **thin**; detail is disclosed progressively in skills + `references/`.
- **One source of truth** (`.claude/skills/`); each tool is a thin adapter, never a copy.
- **Always load the matching skill BEFORE answering** a skill-covered topic.
- A PR isn't "done" when opened — it's done when **CI is green** (`/create-pr` enforces this).

## Files in the kit

| File | Role |
|---|---|
| `bootstrap.sh` | Scaffolder — logic only (token + `__ROWS:...__` substitution); bodies live in `templates/`. Idempotent. |
| `templates/` | Every generated file's content — CLAUDE.md, Makefile, `.gitignore`, service/platform skills, 5 workflow commands. Edit templates here. |
| `VERSION` | Kit version — stamped into `.orchestrator-kit-version` in the generated orchestrator so you know which kit built it. |
| `README.md` | This playbook. |
| `HOW-TO-BUILD-AN-ORCHESTRATOR-claude-en.md` | Full theory + by-hand recipe. |
