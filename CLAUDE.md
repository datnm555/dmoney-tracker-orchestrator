# CLAUDE.md

Orchestrator repo for dmoney-tracker. This repo contains the AI operations brain
(skills, routing, docker compose) — **zero product code**.

## Golden rules

1. **Code lives in the real repos.** All code changes, commits and PRs happen in
   `../dmoney-tracker-be` or `../dmoney-tracker-web` — never in this repo.
2. **Always load the matching skill BEFORE answering.** Do not answer questions
   about the backend, frontend or system architecture from general knowledge.
   Routing table: `agent_docs/skill-routing.md`. When unsure which skill applies,
   load `dmoney-platform` first — it is the system map.
3. Cross-repo contracts (DTO shapes, category/payment codes, resx keys) must be
   changed on BOTH sides in the same piece of work — the platform skill lists them.

## Git flow

- `main` is the default branch in all three repos. Feature work in the be/web
  repos happens on `feature/<name>` branches; this orchestrator repo commits
  directly to `main`.
- The AI agent is authorized to create commits and push to `origin` after each
  completed component/feature/flow that passes its gates (build + tests) —
  no per-push permission needed (owner: datnm555, 2026-07-07).
- Never force-push. Never push failing builds or half-done work.

### Ship flow (be/web) — run automatically after every finished feature

Authorized by the owner (datnm555, 2026-11-11): no per-step confirmation needed.

1. Implement on `feature/<name>` (branched from latest `main`).
2. Gates green: be → `dotnet build DMoney.slnx` (zero warnings) + `dotnet test DMoney.slnx`;
   web → `npm test && npm run build` + `npm run lint` adds no new warnings.
3. Push the feature branch to `origin`.
4. Open a PR against `main` (MCP `github` tools — the local `gh` CLI is logged
   into the wrong account), then **merge it into `main` right away** (merge commit).
   Cross-repo contract changes: merge the be PR before the web PR.
5. Pull `main` locally in the affected repos and deploy with docker:
   `docker compose build <api|web>` (run in background — the CLI can hang after
   "Built"), then `docker compose up -d <api|web>`.
6. Verify: api answers on :5113 (new migrations applied), web returns 200 on
   :8080 and serves the new bundle.
7. Report the PR link(s) and the deploy result to the owner.

If any step fails (red gate, merge conflict, merge blocked, failed build), stop
there and report — never merge or deploy a red build.

## Quick reference

- `make clone-all | pull-all | status | branches | list` — manage sibling repos.
- `docker compose up --build` — full stack (postgres :5432, api :5113, web :8080).
- `/create-pr [be|web|orchestrator]` — gate-check, push and open a PR for the
  current feature branch.
- `.mcp.json` is local-only in every repo (gitignored) — never commit it.
