# How to build an "Orchestrator" with Claude Code — one skill per service, AI that understands the whole system

> **Claude Code edition.** A **general, portable guide** to building a **central
> orchestrator** for **any multi-repo / multi-microservice system**, so that Claude Code
> understands the entire system, with **each service / domain packaged as one "skill"**
> that the agent loads at the right moment. Other agents (Codex, Cursor) can share the same
> `.claude/skills/` source via a thin adapter — see §11.
>
> ⚠️ **Reading convention:** every proper name in this document (Vault22,
> `vault22-backend`, `core/`, skill/repo counts…) is an **illustrative example** taken
> from the original repo where this model runs in production — when applying it to your
> project, **substitute your own service/repo names**.

---

## 0. What an orchestrator IS (and is NOT)

**Orchestrator = one central repo that contains only the "operating brain" for AI**, no
product code.

| Contains | Does NOT contain |
|---|---|
| Skill definitions (1 skill / service / domain) | Product code (lives in the original repos) |
| `CLAUDE.md` — rules + way of working | Business logic |
| Slash commands, hooks, agent config | Build artifacts |
| Routing map (topic → skill, directory → skill) | |
| Offline knowledge base (Jira/Confluence, docs) | |

The real repos are **cloned in as siblings (read-only reference)** via `make clone-all`.
Real code is still changed in the original repos; the orchestrator only *points to* the
code, it never *holds* it.

> At Vault22 today: **89 skills**, **21 repos** (18 in the `22sevengithub` org + 3 in
> `SCV-Autumn`, plus opt-in white-label repos), 0 lines of product code in the orchestrator.
>
> To **carry this model to another project in one command**: use
> [`claude-starter-kit/`](README.md) (`bootstrap.sh`
> generates a thin CLAUDE.md, skill + routing scaffolding, a platform-skill skeleton, and
> generic workflow commands — `/create-pr`, `/pr-review`, `/cross-repo-search`,
> `/status-check`, and `/populate-skill`, which auto-drafts each service skill from its
> actual clone). The kit lives next to this file in the original repo — if you only carry
> this file with you, follow the §6 checklist by hand.

---

## 1. Core philosophy (5 principles)

1. **One skill per service/domain.** Each microservice (or one cross-repo domain)
   = exactly 1 skill. A skill is that service's "operating dossier": architecture,
   build/run commands, code patterns, gotchas, reference files.

2. **Progressive disclosure.** The AI's context is a scarce resource.
   → `CLAUDE.md` must be **thin** (it loads into *every* session). Push detail down into
   skills, and load a skill **only when needed**. Long routing tables also move to their
   own file (`agent_docs/skill-routing.md`), *referenced rather than auto-loaded*.

3. **Three-way triggering.** A skill activates via: **(a)** keyword/topic,
   **(b)** the directory being worked in, **(c)** an explicit `/<skill-name>`. (Details in §4.)

4. **Skills are self-describing.** Each skill's frontmatter `description` contains its
   own "triggers" — the agent reads descriptions to decide whether to load the skill.
   The routing table is only a reinforcement layer for automatic matching.

5. **One source of truth.** Skill content is the **single source** (`.claude/skills/`).
   If other tools join later (Codex, Cursor), each adds only a **thin compatibility
   layer** pointing back to that source — never a duplicated copy. (See §11.)

---

## 2. The orchestrator directory map (live example — substitute your own service names)

```
orchestrator/
├── CLAUDE.md                      # Rules + way of working for Claude Code (loads EVERY session — must be thin)
├── CLAUDE_developer.md            # (gitignored, optional) per-developer personal context — symlinked per dev
├── AGENTS.md                      # (optional) Shared rules for other agents (Codex/Cursor) — see §11
├── .agents/skills -> .claude/skills   # (optional) Symlink: Codex/Cursor see the true skill source
├── README.md                      # Onboarding for newcomers (the first 30 minutes)
├── Makefile                       # clone-all / pull-all / status / branches / clone-whitelabel / vault-* ...
├── claude-starter-kit/            # ★ bootstrap.sh — generates a new orchestrator for another project (see §6)
├── bin/                           # helper CLIs (e.g. `brain` — the developer's second brain)
├── agent_docs/
│   ├── skill-routing.md           # Full routing table (referenced, not auto-loaded)
│   └── local-env-setup.md         # Environment variables, local secrets
├── .claude/
│   ├── skills/                    # ★ 1 directory = 1 skill
│   │   ├── vault22-backend/
│   │   │   ├── SKILL.md           # Frontmatter + main content
│   │   │   └── references/        # Deep docs, loaded on demand (progressive disclosure)
│   │   │       ├── architecture.md
│   │   │       ├── api-patterns.md
│   │   │       └── testing-guide.md
│   │   ├── core-microservices/    # jill/jack/steph/NAPI grouped into 1 skill
│   │   ├── vault22-platform/      # ★ The "whole-system scope" skill (see §5)
│   │   └── ... (89 skills)
│   ├── commands/                  # Slash commands (/create-pr, /cross-repo-search, /pr-review, ...)
│   ├── hooks/                     # "Second brain" hooks: context injection, file locks, logging, doc-sync judge
│   ├── settings.json              # Harness + hooks configuration
│   └── workflows/                 # Multi-agent workflows (skills/vault audit + apply fixes)
├── vault/                         # Offline knowledge base (Jira/Confluence → Obsidian; vault/_brain/ = gitignored)
└── core/  global-website/  ...    # The 21 real repos, cloned as siblings (read-only ref)
```

**Golden rule about code location:** every code change / commit / PR happens in the
**real repo**, NOT in the reference clone inside the orchestrator.

---

## 3. Anatomy of a skill (one SKILL.md per service)

This is the most important part. A minimal skill = one `SKILL.md` file:

```markdown
---
name: vault22-backend
description: Use this skill when working with the Vault22 Core backend repository
  (core/). This includes building, testing, running Briteblue.Api/.Service .NET 8.0,
  the Manager/Repository pattern, NUnit tests, PRs. Triggers include "core repository",
  "Briteblue", "backend API", "customer manager", "MongoDB repository", or working in
  the core/ directory.
---

# Vault22 Backend (Core) Skill

One line: what this service does.

## Overview          ← table: location, framework, solution, DB, port
## Quick Commands    ← build / run / test commands that copy-paste cleanly
## Solution Structure← layers/projects
## Reference Files   ← points to references/*.md (read on demand)
## Key Rules         ← mandatory patterns + gotchas ("DO NOT TOUCH PushManager.cs")
## API Authentication← how to call/log in
## Related Skills    ← links to related skills
```

### The frontmatter `description` is the "trigger set"
- Follow the formula: **"Use this skill when ... Triggers include '<keyword>', '<keyword>',
  or working in the `<dir>/` directory."**
- List **the exact words users actually say** + **directory paths** → the agent matches on them.
- The more specific, the more accurate the match, the fewer false loads.

### What a skill should contain (microservice checklist)
- [ ] **Overview table** — location, framework/version, solution/entry-point, DB, port
- [ ] **Quick commands** — build / run / test (copy-paste runnable)
- [ ] **Architecture & patterns** — Manager/Repository, state machines, naming (e.g. `…Async`)
- [ ] **Boundaries & gotchas** — files never to touch, sharding rules, auth rules
- [ ] **How to test** — test naming convention, filter commands
- [ ] **Related skills** — which services this one depends on / calls
- [ ] **references/** — long docs (architecture, deployment) split out, loaded on demand

### When to merge several services into one skill?
When they are of the same family and usually discussed together. Example:
`core-microservices` groups **4 services** (jill = account refresh, jack = KYC/loans/2FA,
steph = SignalR, NAPI = native API) into 1 skill with a comparison table. Large/standalone
services → their own skill (e.g. `vault22-backend`, `saasport`, `categorisation-service`).

### Progressive disclosure inside a skill
`SKILL.md` keeps the "enough to get started" part. Deep material (e.g. `architecture.md`,
`testing-guide.md`) goes into `references/` and is **only pointed to** — the agent reads
it when genuinely needed. Very large skills can split into `sections/` (e.g. the
`mongodb` skill).

---

## 4. The routing layer — how the agent knows which skill to load, and when

There are 3 trigger paths, declared in `CLAUDE.md` (thin) + `agent_docs/skill-routing.md` (full):

**(a) By topic / keyword** — a `User says... → Use Skill → Examples` table:
```
| MongoDB, Atlas, slow queries, tier downgrade | /mongodb  | "query customer collection", "can we go M20?" |
| VLT22-, work on ticket, fix ticket           | /ticket-worker | "work on VLT22-9700" |
```

**(b) By working directory** — a `Working Directory → Use Skill` table:
```
| core/                         | vault22-backend     | Main backend API |
| core.jill/ core.jack/ ...     | core-microservices  | Supporting microservices |
| global-website/               | vault22-website     | Next.js frontend |
| global-website/components/budget/ | vault22-budget  | (child skill, more specific) |
```
→ Note: the map can **nest** — a more specific subdirectory wins a more specialised skill.

**(c) Manual** — the user/agent types `/<skill-name>` to force-load regardless of the tables.

**Mandatory rule:** *ALWAYS load the matching skill BEFORE answering* — never answer a
skill-covered topic from "general knowledge".

`CLAUDE.md` keeps only a pointer to `skill-routing.md` + a few vital rules → every
session and every subagent stays light.

---

## 5. Understanding the WHOLE system — the "platform" skill (bird's-eye view)

This answers the "understand the scope of the entire system (incl. microservices)" part.
Create **one umbrella skill** (here: `vault22-platform`) that acts as the overall map:

`vault22-platform/SKILL.md` contains:
- **Architecture diagram** of the whole platform (ascii/diagram) — how the tiers talk to each other.
- **Repository classification** — grouped: Backend Services (10), Frontend & Mobile (4),
  AI & Content (2), Infra & Testing (2)... one line per repo: what it does + which skill owns it.
- **Dependency map** — which service calls which (e.g. core ↔ autumn ↔ GTN).
- **Shared infrastructure** — AWS account/region table, database table (which repo uses
  which DB), branch strategy, deploy quick-reference.
- **Skill navigation guide** — "to do X, load skill Y".

Principle: **per-service detail lives in that service's skill; the platform skill keeps
only "map + pointers"** — avoid duplicating content. When the agent needs an overview or
routing → it loads `vault22-platform`; when it goes deep into one service → it jumps to
the specialised skill.

Result: the AI gets **2 levels of awareness** — *zoom-out* (platform skill: big picture,
relationships between microservices) and *zoom-in* (per-service skill: execution detail).

---

## 6. Building an orchestrator for your own system (step-by-step)

> **Shortcut:** [`claude-starter-kit/bootstrap.sh`](README.md)
> automates steps 1–6 in one command; then `/populate-skill`
> auto-drafts each service's `SKILL.md` from the actual clone — you review instead of
> writing from scratch, and `make doctor` lists what's still on placeholders. The steps
> below are the "by hand" version / for understanding the model.

1. **Create an empty orchestrator repo** (no product code). Add a thin `CLAUDE.md` +
   an onboarding `README.md`.

2. **Bring every repo in as a sibling.** Write a `Makefile`:
   - Declare the repo list (`PRIMARY_REPOS`, plus a second org if you have one).
   - Targets `clone-all` (idempotent: skips existing repos), `pull-all`, `status`,
     `branches`, `list`, `clean`. (See this repo's Makefile — `if [ -d ]` guards make
     re-runs safe.)
   - Support `clone-whitelabel PROJECT=<code>` for opt-in repos (white-label/customer).

3. **Map each service → 1 skill.** For every microservice create
   `.claude/skills/<service>/SKILL.md` per the templates in §3 and §10. Small same-family
   services → merge into one skill. Push long docs into `references/`.

4. **Write the routing layer.** In `agent_docs/skill-routing.md`: the topic→skill and
   directory→skill tables for every service. `CLAUDE.md` only points to this file.

5. **Write the umbrella platform skill** (§5): diagram + repo classification +
   dependencies + shared infrastructure.

6. **(Optional) Add cross-cutting pieces:**
   - **Slash commands** (`.claude/commands/`) for repeated workflows: `/create-pr`,
     `/cross-repo-search`, `/status-check`, `/sync-all`.
   - **Hooks** (`.claude/hooks/` + `settings.json`) for automated behaviour (context
     injection at session start, file locks against collisions, logging...).
   - **Knowledge base** (`vault/`) for offline docs (Jira/Confluence/runbooks).

7. **Layer your knowledge** to avoid duplication (see §7).

8. **Test the routing:** try real prompts/topics and `cd` into each directory → the
   right skill should load.

---

## 7. Knowledge layering — put each fact in the right place (no duplication)

| Layer | Location | Public? | Owns |
|---|---|---|---|
| 1. Team-shared knowledge | `vault/{features,proposals,jira,confluence,data-room,people}/` | ✅ committed | Architecture, runbooks, feature designs, who-is-who (`vault/people/`) |
| 2. Tooling & how-to (person-agnostic) | `.claude/skills/*` | ✅ committed | Workflows, commands, per-service patterns |
| 3. Personal / session context | `vault/_brain/` + memory (gitignored) | ❌ | Per-session state, in-flight notes, personal observations |

Rule: **decide which layer owns a fact BEFORE writing it**. If a topic already lives in
layer 1, a skill only **links to it** — never restates the content. A layer-3 brain note
that grows into 5+ team-relevant lines → **promote** it to `vault/`. A skill that needs
facts about a person → reads `vault/people/<slug>.md`, never duplicates them.

---

## 8. Golden rules (DO / DON'T)

**DO**
- Keep `CLAUDE.md` thin; push detail into skills; push deeper detail into `references/`.
- 1 skill = 1 service/domain, with a trigger-rich `description` (keywords + directories).
- Make the Makefile idempotent (safe to re-run).
- Have 1 platform skill as the overall map + specialised skills for detail.
- Every fact lives in **one** layer; everywhere else links to it.

**DON'T**
- ❌ Keep product code in the orchestrator (reference clones only; edit in the real repos).
- ❌ Stuff long routing tables into `CLAUDE.md` (split out `skill-routing.md`).
- ❌ Duplicate content between the platform skill and service skills.
- ❌ Answer a skill-covered topic from general knowledge without loading the skill.
- ❌ Create one "giant skill" for everything — split by service/domain.

---

## 9. Lifecycle & maintenance

- **New repo** → add to `PRIMARY_REPOS` (Makefile) + create a new skill + add a routing
  row + update the classification in the platform skill.
- **Regular pulls** → `make pull-all` so reference clones don't drift from the real repos.
- **Skills evolve** → when new patterns/gotchas appear, update `SKILL.md` (and
  `references/`) — don't let knowledge die in one person's head.
- **Ship a change → document it (ENFORCED by a hook)** → at Vault22, a *Stop-time
  doc-sync judge* (hook) reads the diff whenever you push / open a PR from a real repo
  and **blocks the session from finishing** if the change isn't reflected in
  `vault/features/` and/or the relevant skill. This is the mechanism that keeps skills
  from ever going stale — worth carrying over when you build a new orchestrator.
- **Measure the "match rate"** → occasionally try real prompts and check the agent loads
  the right skill; adjust `description`/routing when it misses.

---

## 10. SKILL.md template (copy to start a new service)

```markdown
---
name: <service-slug>
description: Use this skill when working with <Service Name> (<repo-or-dir>/). Covers
  building, running, testing, the <pattern> architecture, and <key responsibilities>.
  Triggers include "<keyword1>", "<keyword2>", "<keyword3>", or working in the
  <repo-or-dir>/ directory.
---

# <Service Name> Skill

One line: what this service does in the system.

## Overview
| Property | Value |
|----------|-------|
| Location | <path> |
| Framework | <lang/version> |
| Entry point | <solution/app> |
| Database | <db> |
| Port | <port> |

## Quick Commands
```bash
# Build / Run / Test (copy-paste runnable)
```

## Architecture & Patterns
- Main pattern, naming conventions, module boundaries.

## Key Rules & Gotchas
- Files/areas NEVER to touch, sharding/auth rules, common failure modes.

## How to Test
- Test naming convention + run commands.

## Related Skills
- Depends on / calls: `<other-skill>`, `<other-skill>`.

## Reference Files
- `references/architecture.md`, `references/deployment.md` (read on demand).
```

---

## 11. Companion tools alongside Claude Code

This kit scaffolds a **Claude-only** orchestrator. Other agents can reuse the exact same
`.claude/skills/` source — **one source of truth, one thin adapter per tool** — but that
adapter is **not generated here**; add it by hand if you need it:

- **`AGENTS.md` (shared backbone):** a standard many agents read (Codex, Cursor, Aider…).
  Put it at the root. It should point to the real skill source (`.claude/skills/`) +
  routing table (`agent_docs/skill-routing.md`) and state the rule *"when docs mention
  `/skill-name`, load that skill BEFORE answering/acting."*
- **Codex / Cursor:** add the symlink `.agents/skills → .claude/skills` so they see the
  same skills; invoke with `$skill-name`.

Differences between tools live only in **skill-invocation syntax**, NEVER in content —
keep everything in `.claude/skills/` and let each tool point at it.

---

### TL;DR
An orchestrator = a central repo with **no product code**, pulling every repo in as a
sibling, **packaging each service as 1 skill** (a `SKILL.md` with trigger-rich
frontmatter), adding a **routing layer** (topic→skill, directory→skill) so Claude loads
the right skill at the right time, plus **1 platform skill** as the overall map so the AI
understands how all the microservices relate. `CLAUDE.md` stays thin; detail is disclosed
progressively on demand. Other tools (Codex, Cursor) can plug in via a thin adapter
(`AGENTS.md` + a `.agents/skills` symlink) — not scaffolded by this Claude-only kit. To
build one for another project: `claude-starter-kit/bootstrap.sh`.
