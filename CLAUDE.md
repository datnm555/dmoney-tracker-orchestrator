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

## Quick reference

- `make clone-all | pull-all | status | branches | list` — manage sibling repos.
- `docker compose up --build` — full stack (postgres :5432, api :5113, web :8080).
