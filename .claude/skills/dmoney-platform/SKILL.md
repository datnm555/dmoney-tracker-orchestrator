---
name: dmoney-platform
description: Use this skill when you need the bird's-eye view of the dmoney-tracker
  system - how the repos relate, cross-repo contracts, shared infrastructure, ports,
  docker compose, or deciding which service a change belongs to. Triggers include
  "architecture", "system overview", "which repo", "docker compose", "ports",
  "cross-repo", "contract", or working in the dmoney-tracker-orchestrator/ directory.
---

# dmoney-tracker Platform Skill

Personal money tracker (Vietnamese-first), 3 sibling repos, 1 user-facing web app.

## Architecture

```
┌──────────────────────┐     HTTP/JSON (axios, JWT Bearer)     ┌──────────────────────┐
│  dmoney-tracker-web  │ ────────────────────────────────────► │  dmoney-tracker-be   │
│  Vite+React+Tailwind │   VITE_API_URL → http://localhost:5113│  .NET 10 minimal API │
│  + shadcn/ui         │ ◄──────────────────────────────────── │  Clean Arch + CQRS   │
└──────────────────────┘     /resources = ALL UI labels        └──────────┬───────────┘
         :5173 dev / :8080 docker                                         │ EF Core (Npgsql)
                                                                ┌─────────▼───────────┐
                                                                │  postgres :5432      │
                                                                │  db=dmoney           │
                                                                └──────────────────────┘
```

## Repository classification

| Repo | What it is | Skill |
|---|---|---|
| `dmoney-tracker-be` | .NET 10 API: auth (JWT), transactions CRUD, monthly summary, dashboard stats, i18n resources | `dmoney-backend` |
| `dmoney-tracker-web` | React SPA: login/register, dashboard (Tổng quan), transactions (Giao dịch) | `dmoney-web` |
| `dmoney-tracker-orchestrator` | This repo: AI brain + docker compose. No product code | `dmoney-platform` |

## Cross-repo contracts (change BOTH sides together)

| Contract | Backend side | Frontend side |
|---|---|---|
| Response DTO shapes (camelCased by ASP.NET) | `src/Application/Transactions/Data/*.cs` | `src/api/types.ts` |
| Category codes | `Domain/Transactions/TransactionCategories.cs` | `src/utils/categories.ts` |
| Payment method / card type codes | `Domain/Transactions/PaymentMethods.cs`, `CardTypes.cs` | `src/utils/paymentMethods.ts` |
| ALL UI labels + error messages | `Web.Api/Resources/SharedResource.{vi,en}.resx` served at `GET /resources?lang=` | `t(key)` via I18nContext — falls back silently to raw key |
| API base URL | serves on :5113 | `VITE_API_URL` (build arg in docker) |

## Shared infrastructure

- `docker-compose.yml` (this repo): postgres :5432 (user/pass `postgres`/`postgres`,
  db `dmoney`), api :5113 (auto-migrate on), web :8080. `docker compose up --build`.
- Local dev: postgres via `docker compose up -d postgres`, api via
  `dotnet run --project src/Web.Api`, web via `npm run dev` (:5173).
- Branch strategy: work on feature branches in each repo; `main` is default everywhere.

## Skill navigation

- Change data model / endpoint / validation / error code → `dmoney-backend`
- Change UI / page / component / chart / label usage → `dmoney-web`
- Add a user-facing string → BOTH (resx keys in be, `t()` usage in web)
- New repo → add to `REPOS` in Makefile + new skill + row in `agent_docs/skill-routing.md` + row here
