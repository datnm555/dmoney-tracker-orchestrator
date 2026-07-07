# dmoney-tracker Orchestrator + Payment Method + FE Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the AI orchestrator repo per `HOW-TO-BUILD-AN-ORCHESTRATOR.md`, add payment-method support to the .NET backend, and rebuild the React frontend with Tailwind v4 + shadcn/ui to match the approved mockup.

**Architecture:** Three sequential workstreams across three sibling repos: (A) orchestrator = skills + routing + Makefile, no product code; (B) backend follows existing Clean Architecture/CQRS conventions — payment method modeled as validated string codes like the existing `TransactionCategories` pattern; (C) frontend swaps antd → Tailwind v4 + vendored shadcn/ui components + Recharts, page by page so the build stays green at every commit.

**Tech Stack:** GNU Make, Claude Code skills; .NET 10, EF Core + Npgsql, NUnit, Testcontainers; Vite + React 19 + TS, Tailwind v4, shadcn/ui (radix), Recharts, sonner, vitest.

**Spec:** `docs/superpowers/specs/2026-07-07-dmoney-orchestrator-fe-redesign-design.md` (orchestrator repo)

## Global Constraints

- Repo roots: orchestrator `/Users/dat.nguyenmanh/Desktop/dat/my-git/dmoney-tracker/dmoney-tracker-orchestrator`, backend `../dmoney-tracker-be`, frontend `../dmoney-tracker-web`. All paths below are relative to the workstream's repo root.
- Code changes/commits happen in the repo the task names — never commit be/web changes from the orchestrator.
- Backend gate: `dotnet build DMoney.slnx` must pass with ZERO warnings (TreatWarningsAsErrors); `dotnet test tests/Application.UnitTests` for fast loop; full `dotnet test DMoney.slnx` needs Docker running.
- Backend migrations MUST use `--output-dir Database/Migrations`.
- Every user-facing string key must be added to BOTH `src/Web.Api/Resources/SharedResource.vi.resx` AND `.en.resx` (be repo) — FE `t()` falls back silently, tests will NOT catch a missing key.
- Payment method / card type wire values are lowercase string codes: `transfer` | `cash` | `card`; `visa` | `credit` — comment-synced FE↔BE like categories.
- FE theme: primary `#6C4CF1`, zinc neutrals, `--radius: 0.5rem` (8px), font 'Be Vietnam Pro', income `#16a34a`, expense `#dc2626`.
- FE gate: `npm run build` (includes tsc) + `npm test` green at every commit. antd may only be deleted after no file imports it.
- Deviations from mockup (approved in spec/plan): no "＋ Thêm" custom category (BE validates a fixed list); no per-transaction time (BE stores DateOnly — rows show category · payment method instead); dialog keeps date + note fields (functionality preserved); currency select is display-only ₫ VND.

---

## Workstream A — Orchestrator repo

### Task 1: Makefile + README

**Files:**
- Create: `Makefile`
- Modify: `README.md` (full rewrite)

**Interfaces:**
- Produces: `make clone-all | pull-all | status | branches | list` targets operating on sibling repos in the parent directory.

- [ ] **Step 1: Write `Makefile`**

```makefile
# dmoney-tracker orchestrator — sibling repos live in the PARENT directory.
REPOS := dmoney-tracker-be dmoney-tracker-web
GIT_BASE := git@github.com:datnm555
PARENT := ..

.PHONY: help clone-all pull-all status branches list

help:
	@echo "Targets:"
	@echo "  clone-all  Clone missing sibling repos into $(PARENT)/ (idempotent)"
	@echo "  pull-all   git pull --ff-only every sibling repo"
	@echo "  status     git status -sb for every sibling repo"
	@echo "  branches   Current branch of every sibling repo"
	@echo "  list       List managed repos"

clone-all:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "skip  $$repo (already cloned)"; \
		else \
			echo "clone $$repo"; \
			git clone "$(GIT_BASE)/$$repo.git" "$(PARENT)/$$repo"; \
		fi; \
	done

pull-all:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "== $$repo =="; \
			git -C "$(PARENT)/$$repo" pull --ff-only; \
		fi; \
	done

status:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "== $$repo =="; \
			git -C "$(PARENT)/$$repo" status -sb; \
		fi; \
	done

branches:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			printf "%-24s %s\n" "$$repo" "$$(git -C $(PARENT)/$$repo branch --show-current)"; \
		fi; \
	done

list:
	@for repo in $(REPOS); do echo "$$repo"; done
```

- [ ] **Step 2: Verify targets**

Run: `make list && make status && make branches && make clone-all`
Expected: lists both repos; status shows both; clone-all prints `skip` twice (both already exist).

- [ ] **Step 3: Rewrite `README.md`**

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add Makefile README.md
git commit -m "feat: Makefile repo management + onboarding README"
```

### Task 2: CLAUDE.md + AGENTS.md + routing table

**Files:**
- Create: `CLAUDE.md`, `AGENTS.md`, `agent_docs/skill-routing.md`

**Interfaces:**
- Produces: routing contract referenced by all skills; skill names `dmoney-platform`, `dmoney-backend`, `dmoney-web` (Task 3 must use exactly these).

- [ ] **Step 1: Write `CLAUDE.md`** (thin — details live in skills)

```markdown
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
```

- [ ] **Step 2: Write `AGENTS.md`**

```markdown
# AGENTS.md

Shared agent contract for the dmoney-tracker orchestrator (Copilot, Codex, Cursor,
Aider — Claude Code reads CLAUDE.md, same rules).

- Skills (single source of truth) live in `.claude/skills/<name>/SKILL.md`.
  When any doc mentions `/skill-name`, read that skill file BEFORE answering or acting.
- Routing (topic→skill, directory→skill): `agent_docs/skill-routing.md`.
- This repo holds no product code. Make code changes in the sibling repos
  `../dmoney-tracker-be` and `../dmoney-tracker-web`; each has its own CLAUDE.md
  with authoritative per-repo conventions.
- Workflow changes belong in the skill body so every tool stays in sync — do not
  fork tool-specific copies of skill content.
```

- [ ] **Step 3: Write `agent_docs/skill-routing.md`**

```markdown
# Skill Routing

Always load the matching skill BEFORE answering. Manual override: `/dmoney-platform`,
`/dmoney-backend`, `/dmoney-web`.

## By topic

| User says / topic | Skill | Examples |
|---|---|---|
| system architecture, how repos relate, ports, docker, deployment, cross-repo contracts | `dmoney-platform` | "how does web talk to api?", "what runs on 5113?" |
| .NET, API, C#, CQRS, EF Core, migrations, postgres schema, JWT auth, resx, error codes, integration tests | `dmoney-backend` | "add a field to Transaction", "why 401?" |
| React, UI, Tailwind, shadcn, Recharts, vitest, i18n labels, axios, routing, pages | `dmoney-web` | "restyle the dashboard", "add a filter tab" |
| transactions/categories/payment methods (data model + API) | `dmoney-backend` | "validate card type" |
| transactions/categories/payment methods (display + forms) | `dmoney-web` | "the badge shows the wrong label" |

## By working directory

| Working directory | Skill | Notes |
|---|---|---|
| `dmoney-tracker-be/` | `dmoney-backend` | .NET 10 API |
| `dmoney-tracker-web/` | `dmoney-web` | React frontend |
| `dmoney-tracker-orchestrator/` | `dmoney-platform` | this repo — system map |

Cross-repo work (contract changes, full-stack features): load `dmoney-platform`
plus each affected service skill.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md agent_docs/skill-routing.md
git commit -m "feat: thin CLAUDE.md, AGENTS.md backbone and skill routing table"
```

### Task 3: The three skills

**Files:**
- Create: `.claude/skills/dmoney-platform/SKILL.md`
- Create: `.claude/skills/dmoney-backend/SKILL.md`
- Create: `.claude/skills/dmoney-web/SKILL.md`

**Interfaces:**
- Consumes: skill names + routing from Task 2.
- Produces: the loaded-on-demand knowledge layer. Per-repo depth stays in each repo's CLAUDE.md (linked, not copied).

Note: `dmoney-web` is written for the POST-redesign stack (Tailwind/shadcn) since Workstream C lands immediately after.

- [ ] **Step 1: Write `dmoney-platform/SKILL.md`**

```markdown
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
```

- [ ] **Step 2: Write `dmoney-backend/SKILL.md`**

```markdown
---
name: dmoney-backend
description: Use this skill when working with the dmoney-tracker .NET backend
  (dmoney-tracker-be/). Covers building, testing, running the Web.Api, Clean
  Architecture layers, custom CQRS, EF Core migrations, JWT auth, resx i18n and
  error codes. Triggers include "backend", "API", ".NET", "C#", "migration",
  "EF Core", "postgres schema", "JWT", "resx", "error code", "integration test",
  or working in the dmoney-tracker-be/ directory.
---

# dmoney-tracker Backend Skill

.NET 10 API for the money tracker. **Authoritative conventions live in
`../dmoney-tracker-be/CLAUDE.md` — read it before non-trivial work.** This skill is
the quick map.

## Overview

| Property | Value |
|---|---|
| Location | `../dmoney-tracker-be` |
| Framework | .NET 10, C#, minimal APIs |
| Solution | `DMoney.slnx` (5 projects: SharedKernel ← Domain ← Application ← Infrastructure ← Web.Api) |
| Database | PostgreSQL (EF Core + Npgsql), db `dmoney` |
| Port | 5113 |
| Tests | NUnit; unit (mocked DbContext) + integration (Testcontainers, needs Docker) + architecture (NetArchTest) |

## Quick commands

```bash
dotnet build DMoney.slnx                 # ZERO-warnings gate
dotnet test tests/Application.UnitTests  # fast loop, no Docker
dotnet test DMoney.slnx                  # all suites, needs Docker
dotnet run --project src/Web.Api        # :5113, auto-migrates in Development
dotnet dotnet-ef migrations add <Name> --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations
```

## Key rules & gotchas (the ones that bite)

- Custom CQRS, **no MediatR**: `internal sealed` `*CommandHandler`/`*QueryHandler`
  returning `Result<T>` — never throw for domain failures. Register each handler
  explicitly in `Application/DependencyInjection.cs`.
- Migrations MUST use `--output-dir Database/Migrations`.
- `MapInboundClaims = false` + raw `"sub"` claim in `UserContext` are a pair.
- Other users' records → 404, never 403 (isolation via query predicates).
- `Money.Zero()` is a factory, not a shared instance (EF owned-type requirement).
- Every user-facing string: add key to BOTH `SharedResource.vi.resx` and `.en.resx`.
- Domain codes (categories, payment methods, card types) are lowercase strings
  validated against `IReadOnlyList<string> All` — mirror pattern for new code sets.

## Related skills

- `dmoney-platform` — cross-repo contracts (DTOs ↔ types.ts, codes, resx).
- `dmoney-web` — the consumer of every endpoint and resx key.
```

- [ ] **Step 3: Write `dmoney-web/SKILL.md`**

```markdown
---
name: dmoney-web
description: Use this skill when working with the dmoney-tracker React frontend
  (dmoney-tracker-web/). Covers Vite, React 19, TypeScript, Tailwind v4, shadcn/ui,
  Recharts, vitest, axios API layer, i18n labels and routing. Triggers include
  "frontend", "web", "UI", "React", "Tailwind", "shadcn", "component", "page",
  "chart", "vitest", "i18n label", or working in the dmoney-tracker-web/ directory.
---

# dmoney-tracker Web Skill

React SPA (Vietnamese-first). **Authoritative conventions live in
`../dmoney-tracker-web/CLAUDE.md` — read it before non-trivial work.**

## Overview

| Property | Value |
|---|---|
| Location | `../dmoney-tracker-web` |
| Framework | Vite + React 19 + TypeScript |
| UI | Tailwind v4 + shadcn/ui (vendored in `src/components/ui/`), lucide-react icons, sonner toasts |
| Charts | Recharts (pure data transforms in `src/utils/chartData.ts`) |
| Theme | primary `#6C4CF1`, zinc neutrals, radius 8px, font Be Vietnam Pro (`src/index.css`) |
| Tests | vitest + Testing Library (jsdom) |
| Port | 5173 dev / 8080 docker |

## Quick commands

```bash
npm run dev     # :5173, needs api at VITE_API_URL (default http://localhost:5113)
npm test        # vitest run
npm run build   # tsc -b && vite build (type-checks tests too)
npm run lint    # oxlint
```

## Key rules & gotchas

- ALL user-facing strings come from the backend `GET /resources` — `t(key)` falls
  back silently to the raw key; add keys to BOTH resx files in the be repo FIRST.
- `src/api/client.ts` interceptors: Bearer token + `lang` param on every call;
  401 → clear storage + redirect /login. `STORAGE_KEYS` are load-bearing.
- Pages: `/app/dashboard` (Tổng quan), `/app/transactions` (Giao dịch);
  `/app/summary` redirects to transactions. Auth pages: `/login`, `/register`.
- Code sets comment-synced with the be repo: `src/utils/categories.ts`,
  `src/utils/paymentMethods.ts`. DTO mirrors: `src/api/types.ts`.
- shadcn components are vendored — edit `src/components/ui/*` like normal code;
  add new ones with `npx shadcn@latest add -y <name>`.
- Tests mock `../api/resourceApi` so `t()` returns raw keys; assert on keys.

## Related skills

- `dmoney-backend` — API shapes, resx keys, error codes.
- `dmoney-platform` — ports, docker, cross-repo contract list.
```

- [ ] **Step 4: Verify skill frontmatter parses** (each file starts with `---`, has `name:` matching its directory, `description:` mentions triggers + directory)

Run: `head -10 .claude/skills/*/SKILL.md`
Expected: three well-formed frontmatter blocks.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills
git commit -m "feat: dmoney-platform, dmoney-backend, dmoney-web skills"
```

---

## Workstream B — Backend payment method (repo: `../dmoney-tracker-be`)

### Task 4: Domain — code sets, fields, validation (TDD)

**Files:**
- Create: `src/Domain/Transactions/PaymentMethods.cs`, `src/Domain/Transactions/CardTypes.cs`
- Modify: `src/Domain/Transactions/Transaction.cs`, `src/Domain/Transactions/TransactionConstants.cs`, `src/Domain/Transactions/TransactionErrors.cs`
- Test: `tests/Application.UnitTests/Transactions/TransactionTests.cs`

**Interfaces:**
- Produces: `Transaction.Create(Guid userId, DateOnly date, string content, Money credit, Money debit, string? note, string? category = null, string? paymentMethod = null, string? cardType = null, string? bank = null)` and matching `Update(...)`; properties `string PaymentMethod` (never null, defaults `"transfer"`), `string? CardType`, `string? Bank`; constants `PaymentMethods.{Transfer,Cash,Card,All,IsValid,MaxLength}`, `CardTypes.{Visa,Credit,All,IsValid,MaxLength}`, `TransactionConstants.BankMaxLength = 100`; errors `TransactionErrors.{InvalidPaymentMethod,CardTypeRequired,InvalidCardType,CardDetailsNotAllowed,BankTooLong}`.

- [ ] **Step 1: Write failing tests** — open `tests/Application.UnitTests/Transactions/TransactionTests.cs`, match its existing fixture style (NUnit), and add these cases (adapt helper usage for userId/date/money to whatever the file already uses):

```csharp
[Test]
public void Create_WithoutPaymentMethod_DefaultsToTransfer()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Lunch",
        Money.Zero(), Money.Create(50_000m).Value, null);

    Assert.That(result.IsSuccess, Is.True);
    Assert.That(result.Value.PaymentMethod, Is.EqualTo(PaymentMethods.Transfer));
    Assert.That(result.Value.CardType, Is.Null);
    Assert.That(result.Value.Bank, Is.Null);
}

[Test]
public void Create_CardWithTypeAndBank_Succeeds()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Netflix",
        Money.Zero(), Money.Create(260_000m).Value, null,
        "entertainment", PaymentMethods.Card, CardTypes.Visa, "Techcombank");

    Assert.That(result.IsSuccess, Is.True);
    Assert.That(result.Value.PaymentMethod, Is.EqualTo(PaymentMethods.Card));
    Assert.That(result.Value.CardType, Is.EqualTo(CardTypes.Visa));
    Assert.That(result.Value.Bank, Is.EqualTo("Techcombank"));
}

[Test]
public void Create_CardWithoutCardType_Fails()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Netflix",
        Money.Zero(), Money.Create(260_000m).Value, null,
        null, PaymentMethods.Card);

    Assert.That(result.IsFailure, Is.True);
    Assert.That(result.Error, Is.EqualTo(TransactionErrors.CardTypeRequired));
}

[Test]
public void Create_UnknownPaymentMethod_Fails()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Lunch",
        Money.Zero(), Money.Create(50_000m).Value, null,
        null, "crypto");

    Assert.That(result.IsFailure, Is.True);
    Assert.That(result.Error, Is.EqualTo(TransactionErrors.InvalidPaymentMethod));
}

[Test]
public void Create_CardDetailsOnNonCardMethod_Fails()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Lunch",
        Money.Zero(), Money.Create(50_000m).Value, null,
        null, PaymentMethods.Cash, CardTypes.Visa);

    Assert.That(result.IsFailure, Is.True);
    Assert.That(result.Error, Is.EqualTo(TransactionErrors.CardDetailsNotAllowed));
}

[Test]
public void Create_UnknownCardType_Fails()
{
    Result<Transaction> result = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Netflix",
        Money.Zero(), Money.Create(260_000m).Value, null,
        null, PaymentMethods.Card, "amex");

    Assert.That(result.IsFailure, Is.True);
    Assert.That(result.Error, Is.EqualTo(TransactionErrors.InvalidCardType));
}

[Test]
public void Update_CanChangePaymentMethod()
{
    Transaction transaction = Transaction.Create(
        Guid.NewGuid(), new DateOnly(2026, 7, 7), "Lunch",
        Money.Zero(), Money.Create(50_000m).Value, null).Value;

    Result result = transaction.Update(
        transaction.Date, transaction.Content, Money.Zero(),
        Money.Create(50_000m).Value, null,
        null, PaymentMethods.Card, CardTypes.Credit, "VPBank");

    Assert.That(result.IsSuccess, Is.True);
    Assert.That(transaction.PaymentMethod, Is.EqualTo(PaymentMethods.Card));
    Assert.That(transaction.CardType, Is.EqualTo(CardTypes.Credit));
    Assert.That(transaction.Bank, Is.EqualTo("VPBank"));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/Application.UnitTests --filter FullyQualifiedName~TransactionTests`
Expected: compile errors (`PaymentMethods` not defined) — that counts as red.

- [ ] **Step 3: Implement domain code**

`src/Domain/Transactions/PaymentMethods.cs`:

```csharp
namespace Domain.Transactions;

public static class PaymentMethods
{
    public const string Transfer = "transfer";
    public const string Cash = "cash";
    public const string Card = "card";

    public const int MaxLength = 20;

    public static readonly IReadOnlyList<string> All = [Transfer, Cash, Card];

    public static bool IsValid(string paymentMethod) =>
        All.Contains(paymentMethod, StringComparer.Ordinal);
}
```

`src/Domain/Transactions/CardTypes.cs`:

```csharp
namespace Domain.Transactions;

public static class CardTypes
{
    public const string Visa = "visa";
    public const string Credit = "credit";

    public const int MaxLength = 20;

    public static readonly IReadOnlyList<string> All = [Visa, Credit];

    public static bool IsValid(string cardType) =>
        All.Contains(cardType, StringComparer.Ordinal);
}
```

`TransactionConstants.cs` — add:

```csharp
    public const int BankMaxLength = 100;
```

`TransactionErrors.cs` — add:

```csharp
    public static readonly Error InvalidPaymentMethod = Error.Validation(
        "Transactions.InvalidPaymentMethod",
        "Invalid payment method.");

    public static readonly Error CardTypeRequired = Error.Validation(
        "Transactions.CardTypeRequired",
        "Please select a card type for card payments.");

    public static readonly Error InvalidCardType = Error.Validation(
        "Transactions.InvalidCardType",
        "Invalid card type.");

    public static readonly Error CardDetailsNotAllowed = Error.Validation(
        "Transactions.CardDetailsNotAllowed",
        "Card details are only allowed for card payments.");

    public static readonly Error BankTooLong = Error.Validation(
        "Transactions.BankTooLong",
        $"Bank name must be at most {TransactionConstants.BankMaxLength} characters.");
```

`Transaction.cs` — add properties after `Category`:

```csharp
    public string PaymentMethod { get; private set; } = PaymentMethods.Transfer;

    public string? CardType { get; private set; }

    public string? Bank { get; private set; }
```

Extend `Create` (same additions to `Update`):

```csharp
    public static Result<Transaction> Create(
        Guid userId,
        DateOnly date,
        string content,
        Money credit,
        Money debit,
        string? note,
        string? category = null,
        string? paymentMethod = null,
        string? cardType = null,
        string? bank = null)
    {
        string? normalizedCategory = Normalize(category);
        string normalizedPaymentMethod = Normalize(paymentMethod) ?? PaymentMethods.Transfer;
        string? normalizedCardType = Normalize(cardType);
        string? normalizedBank = Normalize(bank);

        Result validation = Validate(
            content, credit, debit, note, normalizedCategory,
            normalizedPaymentMethod, normalizedCardType, normalizedBank);
        if (validation.IsFailure)
        {
            return Result.Failure<Transaction>(validation.Error);
        }

        var transaction = new Transaction
        {
            Id = Guid.CreateVersion7(),
            UserId = userId,
            Date = date,
            Content = content.Trim(),
            Credit = credit,
            Debit = debit,
            Note = Normalize(note),
            Category = normalizedCategory,
            PaymentMethod = normalizedPaymentMethod,
            CardType = normalizedCardType,
            Bank = normalizedBank
        };

        return transaction;
    }
```

`Update` mirrors this: same new parameters with the same defaults, same normalization, assigns `PaymentMethod`/`CardType`/`Bank` alongside the existing assignments.

Extend `Validate` — new signature and appended rules:

```csharp
    private static Result Validate(
        string content,
        Money credit,
        Money debit,
        string? note,
        string? normalizedCategory,
        string paymentMethod,
        string? cardType,
        string? bank)
    {
        // ... existing checks unchanged ...

        if (!PaymentMethods.IsValid(paymentMethod))
        {
            return Result.Failure(TransactionErrors.InvalidPaymentMethod);
        }

        if (paymentMethod == PaymentMethods.Card)
        {
            if (cardType is null)
            {
                return Result.Failure(TransactionErrors.CardTypeRequired);
            }

            if (!CardTypes.IsValid(cardType))
            {
                return Result.Failure(TransactionErrors.InvalidCardType);
            }
        }
        else if (cardType is not null || bank is not null)
        {
            return Result.Failure(TransactionErrors.CardDetailsNotAllowed);
        }

        if ((bank?.Length ?? 0) > TransactionConstants.BankMaxLength)
        {
            return Result.Failure(TransactionErrors.BankTooLong);
        }

        return Result.Success();
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet build DMoney.slnx && dotnet test tests/Application.UnitTests --filter FullyQualifiedName~TransactionTests`
Expected: build zero warnings, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Domain tests/Application.UnitTests
git commit -m "feat: payment method, card type and bank on Transaction domain"
```

### Task 5: Application layer — commands, DTO, query

**Files:**
- Modify: `src/Application/Transactions/CreateTransactionCommand.cs`, `UpdateTransactionCommand.cs`, `CreateTransactionCommandHandler.cs`, `UpdateTransactionCommandHandler.cs`, `Data/TransactionResponse.cs`, `GetTransactionsByMonthQueryHandler.cs`
- Test: `tests/Application.UnitTests/Transactions/CreateTransactionCommandHandlerTests.cs`, `UpdateTransactionCommandHandlerTests.cs`, `GetTransactionsByMonthQueryHandlerTests.cs`

**Interfaces:**
- Consumes: Task 4 domain API.
- Produces: wire contract — commands and `TransactionResponse` gain `string? PaymentMethod, string? CardType, string? Bank` (response's `PaymentMethod` is non-null in practice; keep DTO field `string` for response, `string?` for commands). JSON: `paymentMethod`, `cardType`, `bank`.

- [ ] **Step 1: Write failing test** — in `CreateTransactionCommandHandlerTests.cs`, add (adapting to the file's existing mock setup):

```csharp
[Test]
public async Task Handle_PassesPaymentFieldsToTransaction()
{
    // arrange like the file's existing happy-path test, then:
    var command = new CreateTransactionCommand(
        new DateOnly(2026, 7, 7), "Netflix", 0m, 260_000m, null,
        "entertainment", "card", "visa", "Techcombank");

    Result<Guid> result = await handler.Handle(command, CancellationToken.None);

    Assert.That(result.IsSuccess, Is.True);
    // assert on the Transaction captured by the mocked DbSet.Add:
    Assert.That(captured.PaymentMethod, Is.EqualTo(PaymentMethods.Card));
    Assert.That(captured.CardType, Is.EqualTo(CardTypes.Visa));
    Assert.That(captured.Bank, Is.EqualTo("Techcombank"));
}
```

- [ ] **Step 2: Run to verify red** — `dotnet test tests/Application.UnitTests --filter FullyQualifiedName~CreateTransactionCommandHandlerTests` → compile error (constructor arity).

- [ ] **Step 3: Implement**

`CreateTransactionCommand.cs`:

```csharp
public sealed record CreateTransactionCommand(
    DateOnly Date,
    string Content,
    decimal CreditAmount,
    decimal DebitAmount,
    string? Note,
    string? Category,
    string? PaymentMethod = null,
    string? CardType = null,
    string? Bank = null) : ICommand<Guid>;
```

`UpdateTransactionCommand.cs` — same three trailing parameters after `Category`.

`CreateTransactionCommandHandler.cs` — pass through:

```csharp
        Result<Transaction> transaction = Transaction.Create(
            userId, command.Date, command.Content, credit.Value, debit.Value,
            command.Note, command.Category,
            command.PaymentMethod, command.CardType, command.Bank);
```

`UpdateTransactionCommandHandler.cs` — same pass-through on the `Update(...)` call.

`Data/TransactionResponse.cs`:

```csharp
public sealed record TransactionResponse(
    Guid Id,
    DateOnly Date,
    string Content,
    MoneyResponse Credit,
    MoneyResponse Debit,
    string? Note,
    string? Category,
    string PaymentMethod,
    string? CardType,
    string? Bank);
```

`GetTransactionsByMonthQueryHandler.cs` — extend the projection:

```csharp
            .Select(t => new TransactionResponse(
                t.Id,
                t.Date,
                t.Content,
                new MoneyResponse(t.Credit.Amount, t.Credit.Currency),
                new MoneyResponse(t.Debit.Amount, t.Debit.Currency),
                t.Note,
                t.Category,
                t.PaymentMethod,
                t.CardType,
                t.Bank))
```

Fix any other `TransactionResponse` construction sites the compiler reports the same way.

- [ ] **Step 4: Green + full unit suite**

Run: `dotnet build DMoney.slnx && dotnet test tests/Application.UnitTests`
Expected: zero warnings, all PASS (update any existing tests broken by the new record positions).

- [ ] **Step 5: Commit**

```bash
git add src/Application tests/Application.UnitTests
git commit -m "feat: payment fields through commands, handlers and TransactionResponse"
```

### Task 6: Infrastructure — EF mapping + migration + integration tests

**Files:**
- Modify: `src/Infrastructure/Transactions/TransactionConfiguration.cs`
- Create: `src/Infrastructure/Database/Migrations/<timestamp>_AddPaymentMethod.cs` (generated)
- Test: `tests/Api.IntegrationTests/Transactions/TransactionsEndpointsTests.cs`

**Interfaces:**
- Consumes: Tasks 4–5. Docker must be running for integration tests.
- Produces: columns `PaymentMethod` (varchar(20), not null, default `'transfer'`), `CardType` (varchar(20), null), `Bank` (varchar(100), null) on `transactions`.

- [ ] **Step 1: EF configuration** — add to `TransactionConfiguration.Configure`:

```csharp
        builder.Property(t => t.PaymentMethod)
            .HasMaxLength(PaymentMethods.MaxLength)
            .IsRequired()
            .HasDefaultValue(PaymentMethods.Transfer);

        builder.Property(t => t.CardType)
            .HasMaxLength(CardTypes.MaxLength);

        builder.Property(t => t.Bank)
            .HasMaxLength(TransactionConstants.BankMaxLength);
```

- [ ] **Step 2: Generate migration**

Run:
```bash
dotnet tool restore
dotnet dotnet-ef migrations add AddPaymentMethod --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations
```
Expected: new files under `src/Infrastructure/Database/Migrations/`; inspect the `Up` — three `AddColumn` calls with the defaults above.

- [ ] **Step 3: Write integration tests** — in `TransactionsEndpointsTests.cs`, following the file's existing register+login+create helpers:

```csharp
[Test]
public async Task CreateWithCardPayment_RoundTripsThroughGet()
{
    // authenticated client per existing pattern
    var response = await client.PostAsJsonAsync("/transactions", new
    {
        date = DateOnly.FromDateTime(DateTime.UtcNow).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        content = "Netflix Premium",
        creditAmount = 0,
        debitAmount = 260000,
        note = (string?)null,
        category = "entertainment",
        paymentMethod = "card",
        cardType = "visa",
        bank = "Techcombank"
    });
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.Created));

    string month = DateTime.UtcNow.ToString("yyyy-MM", CultureInfo.InvariantCulture);
    MonthlySummaryResponse? summary =
        await client.GetFromJsonAsync<MonthlySummaryResponse>($"/transactions?month={month}");
    TransactionResponse item = summary!.Items.Single(i => i.Content == "Netflix Premium");
    Assert.That(item.PaymentMethod, Is.EqualTo("card"));
    Assert.That(item.CardType, Is.EqualTo("visa"));
    Assert.That(item.Bank, Is.EqualTo("Techcombank"));
}

[Test]
public async Task CreateCardWithoutCardType_Returns400()
{
    var response = await client.PostAsJsonAsync("/transactions", new
    {
        date = DateOnly.FromDateTime(DateTime.UtcNow).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        content = "Netflix Premium",
        creditAmount = 0,
        debitAmount = 260000,
        note = (string?)null,
        category = (string?)null,
        paymentMethod = "card"
    });
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.BadRequest));
}

[Test]
public async Task CreateWithoutPaymentMethod_DefaultsToTransfer()
{
    var response = await client.PostAsJsonAsync("/transactions", new
    {
        date = DateOnly.FromDateTime(DateTime.UtcNow).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        content = "Lunch",
        creditAmount = 0,
        debitAmount = 50000,
        note = (string?)null,
        category = (string?)null
    });
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.Created));

    string month = DateTime.UtcNow.ToString("yyyy-MM", CultureInfo.InvariantCulture);
    MonthlySummaryResponse? summary =
        await client.GetFromJsonAsync<MonthlySummaryResponse>($"/transactions?month={month}");
    Assert.That(summary!.Items.Single(i => i.Content == "Lunch").PaymentMethod, Is.EqualTo("transfer"));
}
```

- [ ] **Step 4: Run full suite (Docker required)**

Run: `dotnet build DMoney.slnx && dotnet test DMoney.slnx`
Expected: zero warnings; all unit + integration + architecture tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Infrastructure tests/Api.IntegrationTests
git commit -m "feat: persist payment fields with AddPaymentMethod migration"
```

### Task 7: resx keys + docs

**Files:**
- Modify: `src/Web.Api/Resources/SharedResource.vi.resx`, `src/Web.Api/Resources/SharedResource.en.resx`, `CLAUDE.md`, `docs/database-schema.md`

**Interfaces:**
- Produces: every key Workstream C's `t()` calls. Key list is the contract — copy exactly.

- [ ] **Step 1: Add keys to BOTH resx files** (`<data name="KEY" xml:space="preserve"><value>VALUE</value></data>`):

| Key | vi | en |
|---|---|---|
| `payment.method` | Hình thức thanh toán | Payment method |
| `payment.transfer` | Chuyển khoản | Bank transfer |
| `payment.cash` | Tiền mặt | Cash |
| `payment.card` | Thẻ | Card |
| `payment.cardType` | Loại thẻ | Card type |
| `payment.cardType.visa` | VISA | VISA |
| `payment.cardType.credit` | Credit | Credit |
| `payment.bank` | Ngân hàng | Bank |
| `payment.bank.other` | Khác | Other |
| `Transactions.InvalidPaymentMethod` | Hình thức thanh toán không hợp lệ. | Invalid payment method. |
| `Transactions.CardTypeRequired` | Vui lòng chọn loại thẻ khi thanh toán bằng thẻ. | Please select a card type for card payments. |
| `Transactions.InvalidCardType` | Loại thẻ không hợp lệ. | Invalid card type. |
| `Transactions.CardDetailsNotAllowed` | Thông tin thẻ chỉ áp dụng cho hình thức Thẻ. | Card details are only allowed for card payments. |
| `Transactions.BankTooLong` | Tên ngân hàng tối đa 100 ký tự. | Bank name must be at most 100 characters. |
| `menu.transactions` | Giao dịch | Transactions |
| `menu.reports` | Báo cáo | Reports |
| `menu.settings` | Cài đặt | Settings |
| `breadcrumb.home` | Trang chủ | Home |
| `dashboard.totalBalance` | Số dư tổng | Total balance |
| `dashboard.vsLastMonth` | so với tháng trước | vs last month |
| `dashboard.txThisMonth` | giao dịch trong tháng | transactions this month |
| `dashboard.cashflow` | Thu / Chi 6 tháng | Income / expense — 6 months |
| `dashboard.recent` | Giao dịch gần đây | Recent transactions |
| `dashboard.viewAll` | Xem tất cả | View all |
| `transactions.filterAll` | Tất cả | All |
| `transactions.creditThisMonth` | Ghi có tháng này | Money in this month |
| `transactions.debitThisMonth` | Ghi nợ tháng này | Money out this month |
| `transactions.today` | Hôm nay | Today |
| `transactions.count` | giao dịch | transactions |
| `form.moneyIn` | Ghi có | Money in |
| `form.moneyOut` | Ghi nợ | Money out |
| `form.amount` | Số tiền | Amount |
| `form.currency` | Tiền tệ | Currency |
| `form.cardTypeRequired` | Vui lòng chọn loại thẻ | Please select a card type |
| `auth.loginHint` | Nhập email và mật khẩu của bạn | Enter your email and password |
| `auth.forgotPassword` | Quên mật khẩu? | Forgot password? |

Also update existing `app.title` value to `MoneyTrack` in BOTH files (mockup brand).

- [ ] **Step 2: Verify via API**

Run: `dotnet run --project src/Web.Api` (needs postgres up), then
`curl -s 'http://localhost:5113/resources?lang=vi' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['payment.method'], d['app.title'])"`
Expected: `Hình thức thanh toán MoneyTrack`. Stop the server.

- [ ] **Step 3: Update docs** — `CLAUDE.md` cross-repo contract paragraph: add "payment method / card type codes in `Domain/Transactions/PaymentMethods.cs` + `CardTypes.cs` are comment-synced with `src/utils/paymentMethods.ts` in the web repo". Append the three new columns to `docs/database-schema.md`.

- [ ] **Step 4: Commit**

```bash
git add src/Web.Api/Resources CLAUDE.md docs/database-schema.md
git commit -m "feat: resx keys for payment method and redesigned UI labels"
```

---

## Workstream C — Frontend redesign (repo: `../dmoney-tracker-web`)

### Task 8: Tailwind v4 + shadcn/ui foundation (antd still installed)

**Files:**
- Create: `src/index.css`, `components.json`, `src/lib/utils.ts` (CLI), `src/components/ui/*` (CLI)
- Modify: `package.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.app.json`, `index.html`, `src/main.tsx`

- [ ] **Step 1: Install Tailwind + deps**

```bash
npm install tailwindcss @tailwindcss/vite
npm install recharts sonner lucide-react
```

- [ ] **Step 2: Path alias.** `tsconfig.json` — add to the root object:

```json
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] }
  }
```

`tsconfig.app.json` — add the same `baseUrl`/`paths` inside its `compilerOptions`.

`vite.config.ts`:

```ts
/// <reference types="vitest/config" />
import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.ts',
  },
})
```

- [ ] **Step 3: Create `src/index.css`** (shadcn init will extend it):

```css
@import "tailwindcss";
```

Add `import './index.css'` as the FIRST import in `src/main.tsx` (keep the antd imports for now).

- [ ] **Step 4: shadcn init + components**

```bash
npx shadcn@latest init -y -b zinc
npx shadcn@latest add -y button input label card dialog tabs select radio-group badge table dropdown-menu separator alert-dialog sonner
```

Expected: `components.json`, `src/lib/utils.ts`, `src/components/ui/*.tsx` created; `src/index.css` now has `:root`/`.dark` CSS vars and `@theme inline`.

- [ ] **Step 5: Theme overrides** — in `src/index.css`, inside the generated `:root` block, REPLACE the generated values for these vars (delete `.dark` block — no dark mode):

```css
:root {
  --radius: 0.5rem;
  --primary: #6C4CF1;
  --primary-foreground: #ffffff;
  --ring: #6C4CF1;
  /* keep the rest of the generated zinc values */
}
```

Append after the generated `@theme inline` block:

```css
@theme inline {
  --color-income: #16a34a;
  --color-expense: #dc2626;
  --font-sans: 'Be Vietnam Pro', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

body {
  font-family: var(--font-sans);
}
```

- [ ] **Step 6: Font** — in `index.html` `<head>`, set `<html lang="vi">`, `<title>MoneyTrack</title>` and add:

```html
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
```

- [ ] **Step 7: Gate + commit**

Run: `npm run build && npm test`
Expected: build green (antd pages untouched), existing tests pass.

```bash
git add -A
git commit -m "feat: Tailwind v4 + shadcn/ui foundation with MoneyTrack theme"
```

### Task 9: Auth pages + AppLayout (mockup 2a + topbar)

**Files:**
- Modify: `src/pages/LoginPage.tsx`, `src/pages/RegisterPage.tsx`, `src/layouts/AppLayout.tsx`

**Interfaces:**
- Consumes: `useAuth()` (`signIn`, `user`, `signOut`), `useI18n()` (`t`, `lang`, `setLang`), `login`/`register` from `src/api/authApi.ts`, `getApiErrorMessage`, shadcn ui components, `toast` from `sonner`.
- Produces: login navigates to `/app/dashboard`.

- [ ] **Step 1: Rewrite `src/pages/LoginPage.tsx`**

```tsx
import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { login } from '../api/authApi'
import { getApiErrorMessage } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { useI18n } from '../i18n/I18nContext'

export function LoginPage() {
  const { t } = useI18n()
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault()
    setSubmitting(true)
    try {
      const response = await login(identifier, password)
      signIn(response)
      navigate('/app/dashboard', { replace: true })
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 p-4">
      <Card className="w-full max-w-sm">
        <CardHeader className="items-center text-center">
          <span className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-primary text-lg font-extrabold text-primary-foreground">
            ₫
          </span>
          <CardTitle>{t('auth.login')} {t('app.title')}</CardTitle>
          <CardDescription>{t('auth.loginHint')}</CardDescription>
        </CardHeader>
        <form onSubmit={onSubmit}>
          <CardContent className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="identifier">{t('auth.identifier')}</Label>
              <Input
                id="identifier"
                autoComplete="username"
                required
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="password">{t('auth.password')}</Label>
                <span className="text-xs text-muted-foreground">{t('auth.forgotPassword')}</span>
              </div>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
          </CardContent>
          <CardFooter className="mt-4 flex-col gap-3">
            <Button type="submit" className="w-full" disabled={submitting}>
              {t('auth.login')}
            </Button>
            <p className="text-sm text-muted-foreground">
              <Link className="text-primary hover:underline" to="/register">
                {t('auth.noAccount')}
              </Link>
            </p>
          </CardFooter>
        </form>
      </Card>
    </div>
  )
}
```

- [ ] **Step 2: Rewrite `src/pages/RegisterPage.tsx`** — same Card shell and state pattern; read the current file first to keep its exact fields (email/username/password/displayName per `register` signature in `src/api/authApi.ts`) and its post-register navigation behavior; link back to `/login` with `t('auth.hasAccount')` (verify key exists in resx; it does if the current page uses it — reuse whatever key the current page renders).

- [ ] **Step 3: Rewrite `src/layouts/AppLayout.tsx`**

```tsx
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { LogOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { useAuth } from '../auth/AuthContext'
import { useI18n } from '../i18n/I18nContext'

const NAV_ITEMS = [
  { to: '/app/dashboard', key: 'menu.dashboard' },
  { to: '/app/transactions', key: 'menu.transactions' },
] as const

const COMING_SOON = ['menu.reports', 'menu.settings'] as const

export function AppLayout() {
  const { t, lang, setLang } = useI18n()
  const { user, signOut } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  const current = NAV_ITEMS.find((item) => location.pathname.startsWith(item.to))

  return (
    <div className="min-h-screen bg-zinc-50">
      <header className="sticky top-0 z-10 border-b bg-background">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-6 px-4">
          <NavLink to="/app/dashboard" className="flex items-center gap-2 font-bold">
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              ₫
            </span>
            {t('app.title')}
          </NavLink>
          <nav className="hidden items-center gap-1 md:flex">
            {NAV_ITEMS.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  cn(
                    'rounded-md px-3 py-1.5 text-sm font-medium text-muted-foreground hover:text-foreground',
                    isActive && 'bg-primary/10 text-primary',
                  )
                }
              >
                {t(item.key)}
              </NavLink>
            ))}
            {COMING_SOON.map((key) => (
              <span key={key} className="cursor-not-allowed rounded-md px-3 py-1.5 text-sm text-muted-foreground/50">
                {t(key)}
              </span>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-3">
            <span className="hidden text-sm text-muted-foreground lg:inline">
              {t('breadcrumb.home')} / {current ? t(current.key) : ''}
            </span>
            <div className="flex overflow-hidden rounded-md border text-xs font-semibold">
              {(['vi', 'en'] as const).map((code) => (
                <button
                  key={code}
                  type="button"
                  onClick={() => setLang(code)}
                  className={cn(
                    'px-2 py-1 uppercase',
                    lang === code ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-zinc-100',
                  )}
                >
                  {code}
                </button>
              ))}
            </div>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" className="gap-2 px-2">
                  <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary/15 text-xs font-bold text-primary">
                    {(user?.displayName ?? '?').charAt(0).toUpperCase()}
                  </span>
                  <span className="hidden text-sm sm:inline">{user?.displayName}</span>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuLabel>
                  <div className="text-sm">{user?.displayName}</div>
                  <div className="text-xs font-normal text-muted-foreground">{user?.email}</div>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onClick={() => {
                    signOut()
                    navigate('/login')
                  }}
                >
                  <LogOut className="mr-2 h-4 w-4" />
                  {t('auth.logout')}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl p-4 md:p-6">
        <Outlet />
      </main>
    </div>
  )
}
```

- [ ] **Step 4: Gate + commit**

Run: `npm run build && npm test`
Expected: green.

```bash
git add src/pages/LoginPage.tsx src/pages/RegisterPage.tsx src/layouts/AppLayout.tsx
git commit -m "feat: shadcn login/register and MoneyTrack topbar layout"
```

### Task 10: Types, payment codes, transaction dialog (mockup 2c) — TDD

**Files:**
- Create: `src/utils/paymentMethods.ts`
- Modify: `src/api/types.ts`, `src/api/transactionApi.ts`
- Rewrite: `src/components/TransactionFormModal.tsx`, `src/components/TransactionFormModal.test.tsx`

**Interfaces:**
- Produces:
  - `PAYMENT_METHOD_CODES = ['transfer','cash','card']`, `CARD_TYPE_CODES = ['visa','credit']`, `BANK_PRESETS = ['Techcombank','VPBank']`.
  - `TransactionResponse` += `paymentMethod: string; cardType: string | null; bank: string | null`; `TransactionPayload` += same (paymentMethod required).
  - `TransactionFormValues = { date: string; content: string; type: 'in' | 'out'; amount: number; category: string | null; paymentMethod: PaymentMethodCode; cardType: CardTypeCode | null; bank: string | null; note: string | null }` — `onSubmit(values)`; consumer maps to payload (`creditAmount = type==='in' ? amount : 0`, etc.).

- [ ] **Step 1: Contracts.** `src/utils/paymentMethods.ts`:

```ts
// Must stay in sync with Domain/Transactions/PaymentMethods.cs + CardTypes.cs on the backend.
export const PAYMENT_METHOD_CODES = ['transfer', 'cash', 'card'] as const
export type PaymentMethodCode = (typeof PAYMENT_METHOD_CODES)[number]

export const CARD_TYPE_CODES = ['visa', 'credit'] as const
export type CardTypeCode = (typeof CARD_TYPE_CODES)[number]

// UI convenience only; the backend stores bank as free text.
export const BANK_PRESETS = ['Techcombank', 'VPBank'] as const
```

`src/api/types.ts` — extend `TransactionResponse`:

```ts
export interface TransactionResponse {
  id: string
  date: string // YYYY-MM-DD
  content: string
  credit: MoneyResponse
  debit: MoneyResponse
  note: string | null
  category: string | null
  paymentMethod: string
  cardType: string | null
  bank: string | null
}
```

`src/api/transactionApi.ts` — extend `TransactionPayload`:

```ts
export interface TransactionPayload {
  date: string // YYYY-MM-DD
  content: string
  creditAmount: number
  debitAmount: number
  note: string | null
  category: string | null
  paymentMethod: string
  cardType: string | null
  bank: string | null
}
```

- [ ] **Step 2: Write the failing tests** — replace `src/components/TransactionFormModal.test.tsx`:

```tsx
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ReactNode } from 'react'
import { I18nProvider } from '../i18n/I18nContext'
import { TransactionFormModal } from './TransactionFormModal'

vi.mock('../api/resourceApi', () => ({
  getResources: vi.fn().mockResolvedValue({}),
}))

function Wrapper({ children }: { children: ReactNode }) {
  return <I18nProvider>{children}</I18nProvider>
}

function renderModal(onSubmit = vi.fn()) {
  render(
    <Wrapper>
      <TransactionFormModal open editing={null} submitting={false} onSubmit={onSubmit} onCancel={() => {}} />
    </Wrapper>,
  )
  return onSubmit
}

describe('TransactionFormModal', () => {
  it('rejects submit when amount is empty', async () => {
    const onSubmit = renderModal()

    await userEvent.type(await screen.findByLabelText('form.content'), 'Ăn trưa')
    await userEvent.click(screen.getByRole('button', { name: 'summary.submit' }))

    expect(await screen.findByText('form.amountRequired')).toBeInTheDocument()
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('requires a card type when paying by card', async () => {
    const onSubmit = renderModal()

    await userEvent.type(await screen.findByLabelText('form.content'), 'Netflix')
    await userEvent.type(screen.getByLabelText('form.amount'), '260000')
    await userEvent.click(screen.getByRole('radio', { name: 'payment.card' }))
    await userEvent.click(screen.getByRole('button', { name: 'summary.submit' }))

    expect(await screen.findByText('form.cardTypeRequired')).toBeInTheDocument()
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('submits mapped values for a card expense', async () => {
    const onSubmit = renderModal()

    await userEvent.type(await screen.findByLabelText('form.content'), 'Netflix')
    await userEvent.type(screen.getByLabelText('form.amount'), '260000')
    await userEvent.click(screen.getByRole('radio', { name: 'payment.card' }))
    await userEvent.click(await screen.findByRole('radio', { name: 'payment.cardType.visa' }))
    await userEvent.click(screen.getByRole('button', { name: 'Techcombank' }))
    await userEvent.click(screen.getByRole('button', { name: 'summary.submit' }))

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        content: 'Netflix',
        type: 'out',
        amount: 260000,
        paymentMethod: 'card',
        cardType: 'visa',
        bank: 'Techcombank',
      }),
    )
  })

  it('defaults to transfer money-out with no card fields', async () => {
    const onSubmit = renderModal()

    await userEvent.type(await screen.findByLabelText('form.content'), 'Ăn trưa')
    await userEvent.type(screen.getByLabelText('form.amount'), '50000')
    await userEvent.click(screen.getByRole('button', { name: 'summary.submit' }))

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'out',
        amount: 50000,
        paymentMethod: 'transfer',
        cardType: null,
        bank: null,
      }),
    )
  })
})
```

- [ ] **Step 3: Run to verify red** — `npm test -- src/components/TransactionFormModal.test.tsx` → FAIL (old component API).

- [ ] **Step 4: Rewrite `src/components/TransactionFormModal.tsx`**

```tsx
import { useEffect, useMemo, useState } from 'react'
import type { FormEvent } from 'react'
import dayjs from 'dayjs'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { cn } from '@/lib/utils'
import type { TransactionResponse } from '../api/types'
import { useI18n } from '../i18n/I18nContext'
import { CATEGORY_CODES } from '../utils/categories'
import {
  BANK_PRESETS,
  CARD_TYPE_CODES,
  PAYMENT_METHOD_CODES,
} from '../utils/paymentMethods'
import type { CardTypeCode, PaymentMethodCode } from '../utils/paymentMethods'

export interface TransactionFormValues {
  date: string // YYYY-MM-DD
  content: string
  type: 'in' | 'out'
  amount: number
  category: string | null
  paymentMethod: PaymentMethodCode
  cardType: CardTypeCode | null
  bank: string | null
  note: string | null
}

interface Props {
  open: boolean
  editing: TransactionResponse | null
  submitting: boolean
  onSubmit: (values: TransactionFormValues) => void
  onCancel: () => void
}

const formatThousands = (digits: string) => digits.replace(/\B(?=(\d{3})+(?!\d))/g, '.')

export function TransactionFormModal({ open, editing, submitting, onSubmit, onCancel }: Props) {
  const { t } = useI18n()
  const [type, setType] = useState<'in' | 'out'>('out')
  const [date, setDate] = useState('')
  const [content, setContent] = useState('')
  const [amountDigits, setAmountDigits] = useState('')
  const [category, setCategory] = useState<string | null>(null)
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethodCode>('transfer')
  const [cardType, setCardType] = useState<CardTypeCode | null>(null)
  const [bank, setBank] = useState<string | null>(null)
  const [customBank, setCustomBank] = useState(false)
  const [note, setNote] = useState('')
  const [errors, setErrors] = useState<Record<string, string>>({})

  useEffect(() => {
    if (!open) return
    setErrors({})
    setCustomBank(false)
    if (editing) {
      const isIncome = editing.credit.amount > 0
      setType(isIncome ? 'in' : 'out')
      setDate(editing.date)
      setContent(editing.content)
      setAmountDigits(String(isIncome ? editing.credit.amount : editing.debit.amount))
      setCategory(editing.category)
      setPaymentMethod((editing.paymentMethod as PaymentMethodCode) ?? 'transfer')
      setCardType((editing.cardType as CardTypeCode) ?? null)
      setBank(editing.bank)
      setCustomBank(editing.bank !== null && !BANK_PRESETS.includes(editing.bank as (typeof BANK_PRESETS)[number]))
      setNote(editing.note ?? '')
    } else {
      setType('out')
      setDate(dayjs().format('YYYY-MM-DD'))
      setContent('')
      setAmountDigits('')
      setCategory(null)
      setPaymentMethod('transfer')
      setCardType(null)
      setBank(null)
      setNote('')
    }
  }, [open, editing])

  const amount = useMemo(() => Number(amountDigits || '0'), [amountDigits])

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault()
    const nextErrors: Record<string, string> = {}
    if (!content.trim()) nextErrors.content = t('form.contentRequired')
    if (amount <= 0) nextErrors.amount = t('form.amountRequired')
    if (paymentMethod === 'card' && !cardType) nextErrors.cardType = t('form.cardTypeRequired')
    setErrors(nextErrors)
    if (Object.keys(nextErrors).length > 0) return

    onSubmit({
      date,
      content: content.trim(),
      type,
      amount,
      category,
      paymentMethod,
      cardType: paymentMethod === 'card' ? cardType : null,
      bank: paymentMethod === 'card' ? (bank?.trim() || null) : null,
      note: note.trim() || null,
    })
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onCancel()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{editing ? t('summary.editTitle') : t('summary.createTitle')}</DialogTitle>
          <DialogDescription>{t('summary.createTitle')}</DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="grid gap-4">
          <div className="grid grid-cols-2 gap-1 rounded-lg bg-zinc-100 p-1">
            {(['out', 'in'] as const).map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => setType(value)}
                className={cn(
                  'rounded-md px-3 py-1.5 text-sm font-medium',
                  type === value
                    ? value === 'out'
                      ? 'bg-white text-expense shadow-sm'
                      : 'bg-white text-income shadow-sm'
                    : 'text-muted-foreground',
                )}
              >
                {value === 'out' ? t('form.moneyOut') : t('form.moneyIn')}
              </button>
            ))}
          </div>

          <div className="grid gap-2">
            <Label htmlFor="tx-date">{t('form.date')}</Label>
            <Input id="tx-date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="tx-content">{t('form.content')}</Label>
            <Input id="tx-content" maxLength={500} value={content} onChange={(e) => setContent(e.target.value)} />
            {errors.content && <p className="text-xs text-expense">{errors.content}</p>}
          </div>

          <div className="grid grid-cols-[1fr_auto] gap-2">
            <div className="grid gap-2">
              <Label htmlFor="tx-amount">{t('form.amount')}</Label>
              <Input
                id="tx-amount"
                inputMode="numeric"
                value={formatThousands(amountDigits)}
                onChange={(e) => setAmountDigits(e.target.value.replace(/\D/g, ''))}
              />
              {errors.amount && <p className="text-xs text-expense">{errors.amount}</p>}
            </div>
            <div className="grid gap-2">
              <Label>{t('form.currency')}</Label>
              <div className="flex h-9 items-center rounded-md border px-3 text-sm text-muted-foreground">₫ VND</div>
            </div>
          </div>

          <div className="grid gap-2">
            <Label>{t('form.category')}</Label>
            <div className="flex flex-wrap gap-1.5">
              {CATEGORY_CODES.map((code) => (
                <button key={code} type="button" onClick={() => setCategory(category === code ? null : code)}>
                  <Badge variant={category === code ? 'default' : 'outline'}>{t(`category.${code}`)}</Badge>
                </button>
              ))}
            </div>
          </div>

          <div className="grid gap-2">
            <Label>{t('payment.method')}</Label>
            <RadioGroup
              value={paymentMethod}
              onValueChange={(value) => {
                setPaymentMethod(value as PaymentMethodCode)
                if (value !== 'card') {
                  setCardType(null)
                  setBank(null)
                  setCustomBank(false)
                }
              }}
              className="grid grid-cols-3 gap-2"
            >
              {PAYMENT_METHOD_CODES.map((code) => (
                <Label
                  key={code}
                  className={cn(
                    'flex cursor-pointer items-center justify-center gap-2 rounded-md border px-2 py-2 text-sm',
                    paymentMethod === code && 'border-primary bg-primary/5 text-primary',
                  )}
                >
                  <RadioGroupItem value={code} className="sr-only" />
                  {t(`payment.${code}`)}
                </Label>
              ))}
            </RadioGroup>
          </div>

          {paymentMethod === 'card' && (
            <>
              <div className="grid gap-2">
                <Label>{t('payment.cardType')}</Label>
                <RadioGroup
                  value={cardType ?? ''}
                  onValueChange={(value) => setCardType(value as CardTypeCode)}
                  className="grid grid-cols-2 gap-2"
                >
                  {CARD_TYPE_CODES.map((code) => (
                    <Label
                      key={code}
                      className={cn(
                        'flex cursor-pointer items-center justify-center rounded-md border px-2 py-2 text-sm uppercase',
                        cardType === code && 'border-primary bg-primary/5 text-primary',
                      )}
                    >
                      <RadioGroupItem value={code} className="sr-only" />
                      {t(`payment.cardType.${code}`)}
                    </Label>
                  ))}
                </RadioGroup>
                {errors.cardType && <p className="text-xs text-expense">{errors.cardType}</p>}
              </div>
              <div className="grid gap-2">
                <Label>{t('payment.bank')}</Label>
                <div className="flex flex-wrap gap-1.5">
                  {BANK_PRESETS.map((preset) => (
                    <button
                      key={preset}
                      type="button"
                      onClick={() => {
                        setBank(preset)
                        setCustomBank(false)
                      }}
                    >
                      <Badge variant={bank === preset && !customBank ? 'default' : 'outline'}>{preset}</Badge>
                    </button>
                  ))}
                  <button
                    type="button"
                    onClick={() => {
                      setCustomBank(true)
                      setBank(null)
                    }}
                  >
                    <Badge variant={customBank ? 'default' : 'outline'}>＋ {t('payment.bank.other')}</Badge>
                  </button>
                </div>
                {customBank && (
                  <Input
                    aria-label={t('payment.bank')}
                    maxLength={100}
                    value={bank ?? ''}
                    onChange={(e) => setBank(e.target.value)}
                  />
                )}
              </div>
            </>
          )}

          <div className="grid gap-2">
            <Label htmlFor="tx-note">{t('form.note')}</Label>
            <textarea
              id="tx-note"
              rows={2}
              maxLength={1000}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onCancel}>
              {t('summary.cancel')}
            </Button>
            <Button type="submit" disabled={submitting}>
              {t('summary.submit')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
```

- [ ] **Step 5: Run tests to verify green**

Run: `npm test -- src/components/TransactionFormModal.test.tsx`
Expected: 4 PASS. (If radix Dialog needs it, add `ResizeObserver`/`scrollIntoView`/`hasPointerCapture` stubs to `src/test/setup.ts` — keep the existing matchMedia stub.)

- [ ] **Step 6: Fix SummaryPage compile break** — SummaryPage still uses the old `TransactionFormValues`. Patch its `handleSubmit` mapping so `npm run build` stays green (it is deleted in Task 12):

```ts
    const payload = {
      date: values.date,
      content: values.content,
      creditAmount: values.type === 'in' ? values.amount : 0,
      debitAmount: values.type === 'out' ? values.amount : 0,
      note: values.note,
      category: values.category,
      paymentMethod: values.paymentMethod,
      cardType: values.cardType,
      bank: values.bank,
    }
```

- [ ] **Step 7: Gate + commit**

Run: `npm run build && npm test`
Expected: green.

```bash
git add src/utils/paymentMethods.ts src/api src/components src/pages/SummaryPage.tsx src/test
git commit -m "feat: payment-aware transaction dialog with shadcn Dialog"
```

### Task 11: Dashboard (mockup 2b) — TDD on chart transform

**Files:**
- Modify: `src/utils/chartData.ts`, `src/utils/chartData.test.ts`, `src/pages/DashboardPage.tsx` (rewrite)

**Interfaces:**
- Consumes: `getDashboardStats(month)`, `getMonthlySummary(month)`, `formatMoney`, `TransactionFormModal` (Task 10), `createTransaction`.
- Produces: `toIncomeExpenseBars(monthly: MonthlyStat[]): { month: string; income: number; expense: number }[]` with `month` rendered as `T<n>` (e.g. `2026-07` → `T7`).

- [ ] **Step 1: Failing test** — add to `src/utils/chartData.test.ts`:

```ts
import { toIncomeExpenseBars } from './chartData'

describe('toIncomeExpenseBars', () => {
  it('maps monthly stats to T-labelled income/expense rows', () => {
    const monthly = [
      {
        month: '2026-06',
        totalCredit: { amount: 100, currency: 'VND' },
        totalDebit: { amount: 40, currency: 'VND' },
        balance: { amount: 60, currency: 'VND' },
      },
      {
        month: '2026-07',
        totalCredit: { amount: 200, currency: 'VND' },
        totalDebit: { amount: 50, currency: 'VND' },
        balance: { amount: 150, currency: 'VND' },
      },
    ]
    expect(toIncomeExpenseBars(monthly)).toEqual([
      { month: 'T6', income: 100, expense: 40 },
      { month: 'T7', income: 200, expense: 50 },
    ])
  })
})
```

- [ ] **Step 2: Red** — `npm test -- src/utils/chartData.test.ts` → FAIL (not exported).

- [ ] **Step 3: Implement** — add to `src/utils/chartData.ts`:

```ts
export interface IncomeExpenseDatum {
  month: string
  income: number
  expense: number
}

export function toIncomeExpenseBars(monthly: MonthlyStat[]): IncomeExpenseDatum[] {
  return monthly.map((m) => ({
    month: `T${Number(m.month.slice(5))}`,
    income: m.totalCredit.amount,
    expense: m.totalDebit.amount,
  }))
}
```

- [ ] **Step 4: Green** — `npm test -- src/utils/chartData.test.ts` → PASS.

- [ ] **Step 5: Rewrite `src/pages/DashboardPage.tsx`**

```tsx
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import dayjs from 'dayjs'
import type { Dayjs } from 'dayjs'
import { Plus } from 'lucide-react'
import { toast } from 'sonner'
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { getApiErrorMessage } from '../api/client'
import { createTransaction, getDashboardStats, getMonthlySummary } from '../api/transactionApi'
import type { DashboardStatsResponse, MonthlySummaryResponse } from '../api/types'
import { TransactionFormModal } from '../components/TransactionFormModal'
import type { TransactionFormValues } from '../components/TransactionFormModal'
import { useI18n } from '../i18n/I18nContext'
import { toIncomeExpenseBars } from '../utils/chartData'
import { formatMoney } from '../utils/money'
import { paymentLabel } from '../utils/paymentLabel'

const vnd = (amount: number) => formatMoney({ amount, currency: 'VND' })

export function DashboardPage() {
  const { t, lang } = useI18n()
  const [month, setMonth] = useState<Dayjs>(dayjs())
  const [stats, setStats] = useState<DashboardStatsResponse | null>(null)
  const [summary, setSummary] = useState<MonthlySummaryResponse | null>(null)
  const [modalOpen, setModalOpen] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  const load = useCallback(async () => {
    try {
      const key = month.format('YYYY-MM')
      const [nextStats, nextSummary] = await Promise.all([getDashboardStats(key), getMonthlySummary(key)])
      setStats(nextStats)
      setSummary(nextSummary)
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }, [month, t])

  useEffect(() => {
    void load()
  }, [load])

  const handleCreate = async (values: TransactionFormValues) => {
    setSubmitting(true)
    try {
      await createTransaction({
        date: values.date,
        content: values.content,
        creditAmount: values.type === 'in' ? values.amount : 0,
        debitAmount: values.type === 'out' ? values.amount : 0,
        note: values.note,
        category: values.category,
        paymentMethod: values.paymentMethod,
        cardType: values.cardType,
        bank: values.bank,
      })
      setModalOpen(false)
      await load()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    } finally {
      setSubmitting(false)
    }
  }

  const monthTabs = [2, 1, 0].map((offset) => dayjs().subtract(offset, 'month'))
  const bars = stats ? toIncomeExpenseBars(stats.monthly) : []
  const current = stats?.monthly.at(-1)
  const previous = stats?.monthly.at(-2)
  const balanceDelta =
    current && previous && previous.balance.amount !== 0
      ? ((current.balance.amount - previous.balance.amount) / Math.abs(previous.balance.amount)) * 100
      : null
  const creditCount = summary?.items.filter((i) => i.credit.amount > 0).length ?? 0
  const debitCount = summary?.items.filter((i) => i.debit.amount > 0).length ?? 0
  const recent = summary?.items.slice(0, 4) ?? []

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold">{t('dashboard.title')}</h1>
          <p className="text-sm capitalize text-muted-foreground">
            {month.toDate().toLocaleDateString(lang === 'vi' ? 'vi-VN' : 'en-US', {
              weekday: 'long',
              day: 'numeric',
              month: 'long',
              year: 'numeric',
            })}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Tabs value={month.format('YYYY-MM')} onValueChange={(value) => setMonth(dayjs(`${value}-01`))}>
            <TabsList>
              {monthTabs.map((m) => (
                <TabsTrigger key={m.format('YYYY-MM')} value={m.format('YYYY-MM')}>
                  T{m.month() + 1}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <Button onClick={() => setModalOpen(true)}>
            <Plus className="mr-1 h-4 w-4" />
            {t('summary.create')}
          </Button>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{t('dashboard.totalBalance')}</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary ? formatMoney(summary.balance) : '—'}</div>
            {balanceDelta !== null && (
              <p className={balanceDelta >= 0 ? 'text-xs text-income' : 'text-xs text-expense'}>
                {balanceDelta >= 0 ? '+' : ''}
                {balanceDelta.toFixed(1)}% {t('dashboard.vsLastMonth')}
              </p>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{t('summary.colCredit')}</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-income">
              +{summary ? formatMoney(summary.totalCredit) : '—'}
            </div>
            <p className="text-xs text-muted-foreground">
              {creditCount} {t('dashboard.txThisMonth')}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{t('summary.colDebit')}</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-expense">
              −{summary ? formatMoney(summary.totalDebit) : '—'}
            </div>
            <p className="text-xs text-muted-foreground">
              {debitCount} {t('dashboard.txThisMonth')}
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t('dashboard.cashflow')}</CardTitle>
        </CardHeader>
        <CardContent className="h-72">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={bars}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e4e4e7" />
              <XAxis dataKey="month" tickLine={false} axisLine={false} fontSize={12} />
              <YAxis tickFormatter={vnd} tickLine={false} axisLine={false} fontSize={12} width={90} />
              <Tooltip formatter={(value) => vnd(Number(value))} />
              <Bar dataKey="income" name={t('summary.colCredit')} fill="#16a34a" radius={[4, 4, 0, 0]} />
              <Bar dataKey="expense" name={t('summary.colDebit')} fill="#dc2626" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle className="text-base">{t('dashboard.recent')}</CardTitle>
          <Link to="/app/transactions" className="text-sm text-primary hover:underline">
            {t('dashboard.viewAll')}
          </Link>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t('summary.colContent')}</TableHead>
                <TableHead>{t('payment.method')}</TableHead>
                <TableHead className="text-right">{t('form.amount')}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {recent.map((tx) => (
                <TableRow key={tx.id}>
                  <TableCell>
                    <div className="font-medium">{tx.content}</div>
                    <div className="text-xs text-muted-foreground">{dayjs(tx.date).format('DD/MM')}</div>
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">{paymentLabel(tx, t)}</Badge>
                  </TableCell>
                  <TableCell
                    className={
                      tx.credit.amount > 0 ? 'text-right font-medium text-income' : 'text-right font-medium text-expense'
                    }
                  >
                    {tx.credit.amount > 0 ? `+${formatMoney(tx.credit)}` : `−${formatMoney(tx.debit)}`}
                  </TableCell>
                </TableRow>
              ))}
              {recent.length === 0 && (
                <TableRow>
                  <TableCell colSpan={3} className="text-center text-muted-foreground">
                    {t('summary.empty')}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <TransactionFormModal
        open={modalOpen}
        editing={null}
        submitting={submitting}
        onSubmit={handleCreate}
        onCancel={() => setModalOpen(false)}
      />
    </div>
  )
}
```

- [ ] **Step 6: Create `src/utils/paymentLabel.ts`** (shared by Dashboard + Transactions):

```ts
import type { TransactionResponse } from '../api/types'

export function paymentLabel(tx: TransactionResponse, t: (key: string) => string): string {
  if (tx.paymentMethod === 'card') {
    const type = tx.cardType ? ` ${t(`payment.cardType.${tx.cardType}`)}` : ''
    return `${t('payment.card')}${type}`
  }
  return t(`payment.${tx.paymentMethod}`)
}
```

- [ ] **Step 7: Gate + commit**

Run: `npm run build && npm test`
Expected: green.

```bash
git add src/utils src/pages/DashboardPage.tsx
git commit -m "feat: MoneyTrack dashboard with stat cards, Recharts cashflow and recent table"
```

### Task 12: Transactions page (mockup 2d) + routes — TDD on grouping

**Files:**
- Create: `src/utils/transactionGroups.ts`, `src/utils/transactionGroups.test.ts`, `src/pages/TransactionsPage.tsx`
- Modify: `src/App.tsx`
- Delete: `src/pages/SummaryPage.tsx`

**Interfaces:**
- Produces: `groupTransactionsByDay(items: TransactionResponse[]): DayGroup[]` where `DayGroup = { date: string; net: number; items: TransactionResponse[] }`, sorted by date desc, `net` = sum(credit) − sum(debit) of the day. Route `/app/transactions`; `/app/summary` → redirect.

- [ ] **Step 1: Failing test** — `src/utils/transactionGroups.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import type { TransactionResponse } from '../api/types'
import { groupTransactionsByDay } from './transactionGroups'

const tx = (id: string, date: string, credit: number, debit: number): TransactionResponse => ({
  id,
  date,
  content: id,
  credit: { amount: credit, currency: 'VND' },
  debit: { amount: debit, currency: 'VND' },
  note: null,
  category: null,
  paymentMethod: 'transfer',
  cardType: null,
  bank: null,
})

describe('groupTransactionsByDay', () => {
  it('groups by date desc with net per day', () => {
    const groups = groupTransactionsByDay([
      tx('a', '2026-07-07', 0, 1_200_000),
      tx('b', '2026-07-05', 28_000_000, 0),
      tx('c', '2026-07-07', 0, 65_000),
    ])

    expect(groups.map((g) => g.date)).toEqual(['2026-07-07', '2026-07-05'])
    expect(groups[0].net).toBe(-1_265_000)
    expect(groups[0].items.map((i) => i.id)).toEqual(['a', 'c'])
    expect(groups[1].net).toBe(28_000_000)
  })
})
```

- [ ] **Step 2: Red** — `npm test -- src/utils/transactionGroups.test.ts` → FAIL.

- [ ] **Step 3: Implement `src/utils/transactionGroups.ts`**

```ts
import type { TransactionResponse } from '../api/types'

export interface DayGroup {
  date: string
  net: number
  items: TransactionResponse[]
}

export function groupTransactionsByDay(items: TransactionResponse[]): DayGroup[] {
  const byDate = new Map<string, TransactionResponse[]>()
  for (const item of items) {
    const bucket = byDate.get(item.date) ?? []
    bucket.push(item)
    byDate.set(item.date, bucket)
  }
  return [...byDate.entries()]
    .sort(([a], [b]) => (a < b ? 1 : -1))
    .map(([date, dayItems]) => ({
      date,
      net: dayItems.reduce((sum, i) => sum + i.credit.amount - i.debit.amount, 0),
      items: dayItems,
    }))
}
```

- [ ] **Step 4: Green** — `npm test -- src/utils/transactionGroups.test.ts` → PASS.

- [ ] **Step 5: Create `src/pages/TransactionsPage.tsx`** — carries over SummaryPage's load/create/update/delete logic:

```tsx
import { useCallback, useEffect, useState } from 'react'
import dayjs from 'dayjs'
import type { Dayjs } from 'dayjs'
import { MoreHorizontal, Plus } from 'lucide-react'
import { toast } from 'sonner'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { getApiErrorMessage } from '../api/client'
import {
  createTransaction,
  deleteTransaction,
  getMonthlySummary,
  updateTransaction,
} from '../api/transactionApi'
import type { MonthlySummaryResponse, TransactionResponse } from '../api/types'
import { TransactionFormModal } from '../components/TransactionFormModal'
import type { TransactionFormValues } from '../components/TransactionFormModal'
import { useI18n } from '../i18n/I18nContext'
import { formatMoney } from '../utils/money'
import { paymentLabel } from '../utils/paymentLabel'
import { groupTransactionsByDay } from '../utils/transactionGroups'

type Filter = 'all' | 'in' | 'out'

export function TransactionsPage() {
  const { t, lang } = useI18n()
  const [month, setMonth] = useState<Dayjs>(dayjs())
  const [summary, setSummary] = useState<MonthlySummaryResponse | null>(null)
  const [filter, setFilter] = useState<Filter>('all')
  const [modalOpen, setModalOpen] = useState(false)
  const [editing, setEditing] = useState<TransactionResponse | null>(null)
  const [deleting, setDeleting] = useState<TransactionResponse | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const load = useCallback(async () => {
    try {
      setSummary(await getMonthlySummary(month.format('YYYY-MM')))
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }, [month, t])

  useEffect(() => {
    void load()
  }, [load])

  const handleSubmit = async (values: TransactionFormValues) => {
    const payload = {
      date: values.date,
      content: values.content,
      creditAmount: values.type === 'in' ? values.amount : 0,
      debitAmount: values.type === 'out' ? values.amount : 0,
      note: values.note,
      category: values.category,
      paymentMethod: values.paymentMethod,
      cardType: values.cardType,
      bank: values.bank,
    }
    setSubmitting(true)
    try {
      if (editing) {
        await updateTransaction(editing.id, payload)
      } else {
        await createTransaction(payload)
      }
      setModalOpen(false)
      setEditing(null)
      await load()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    } finally {
      setSubmitting(false)
    }
  }

  const handleDelete = async () => {
    if (!deleting) return
    try {
      await deleteTransaction(deleting.id)
      setDeleting(null)
      await load()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }

  const items = (summary?.items ?? []).filter((tx) =>
    filter === 'all' ? true : filter === 'in' ? tx.credit.amount > 0 : tx.debit.amount > 0,
  )
  const groups = groupTransactionsByDay(items)
  const today = dayjs().format('YYYY-MM-DD')

  const dayLabel = (date: string) => {
    if (date === today) return `${t('transactions.today')} · ${dayjs(date).format('DD/MM')}`
    const weekday = new Date(`${date}T00:00:00`).toLocaleDateString(lang === 'vi' ? 'vi-VN' : 'en-US', {
      weekday: 'long',
    })
    return `${weekday.charAt(0).toUpperCase()}${weekday.slice(1)} · ${dayjs(date).format('DD/MM')}`
  }

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold">{t('menu.transactions')}</h1>
          <p className="text-sm text-muted-foreground">
            {month.startOf('month').format('DD/MM')} → {month.isSame(dayjs(), 'month') ? dayjs().format('DD/MM/YYYY') : month.endOf('month').format('DD/MM/YYYY')} ·{' '}
            {summary?.items.length ?? 0} {t('transactions.count')}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Tabs value={filter} onValueChange={(value) => setFilter(value as Filter)}>
            <TabsList>
              <TabsTrigger value="all">{t('transactions.filterAll')}</TabsTrigger>
              <TabsTrigger value="in">↑ {t('form.moneyIn')}</TabsTrigger>
              <TabsTrigger value="out">↓ {t('form.moneyOut')}</TabsTrigger>
            </TabsList>
          </Tabs>
          <Input
            type="month"
            className="w-40"
            value={month.format('YYYY-MM')}
            onChange={(e) => e.target.value && setMonth(dayjs(`${e.target.value}-01`))}
          />
          <Button
            onClick={() => {
              setEditing(null)
              setModalOpen(true)
            }}
          >
            <Plus className="mr-1 h-4 w-4" />
            {t('summary.create')}
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap gap-4 text-sm">
        <span>
          {t('transactions.creditThisMonth')}:{' '}
          <strong className="text-income">+{summary ? formatMoney(summary.totalCredit) : '—'}</strong>
        </span>
        <span>
          {t('transactions.debitThisMonth')}:{' '}
          <strong className="text-expense">−{summary ? formatMoney(summary.totalDebit) : '—'}</strong>
        </span>
      </div>

      {groups.length === 0 && (
        <Card>
          <CardContent className="py-10 text-center text-muted-foreground">{t('summary.empty')}</CardContent>
        </Card>
      )}

      {groups.map((group) => (
        <div key={group.date} className="grid gap-2">
          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <span className="font-medium">{dayLabel(group.date)}</span>
            <span className={group.net >= 0 ? 'font-semibold text-income' : 'font-semibold text-expense'}>
              {group.net >= 0 ? '+' : '−'}
              {formatMoney({ amount: Math.abs(group.net), currency: 'VND' })}
            </span>
          </div>
          <Card>
            <CardContent className="divide-y p-0">
              {group.items.map((tx) => (
                <div key={tx.id} className="flex items-center gap-3 px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium">{tx.content}</div>
                    <div className="text-xs text-muted-foreground">
                      {tx.category ? `${t(`category.${tx.category}`)} · ` : ''}
                      {paymentLabel(tx, t)}
                    </div>
                  </div>
                  <Badge variant="outline" className="hidden sm:inline-flex">
                    {paymentLabel(tx, t)}
                  </Badge>
                  <span
                    className={
                      tx.credit.amount > 0 ? 'font-semibold text-income' : 'font-semibold text-expense'
                    }
                  >
                    {tx.credit.amount > 0 ? `+${formatMoney(tx.credit)}` : `−${formatMoney(tx.debit)}`}
                  </span>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon" className="h-8 w-8">
                        <MoreHorizontal className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        onClick={() => {
                          setEditing(tx)
                          setModalOpen(true)
                        }}
                      >
                        {t('summary.edit')}
                      </DropdownMenuItem>
                      <DropdownMenuItem className="text-expense" onClick={() => setDeleting(tx)}>
                        {t('summary.delete')}
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              ))}
            </CardContent>
          </Card>
        </div>
      ))}

      <TransactionFormModal
        open={modalOpen}
        editing={editing}
        submitting={submitting}
        onSubmit={handleSubmit}
        onCancel={() => {
          setModalOpen(false)
          setEditing(null)
        }}
      />

      <AlertDialog open={deleting !== null} onOpenChange={(next) => !next && setDeleting(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('summary.deleteConfirm')}</AlertDialogTitle>
            <AlertDialogDescription>{deleting?.content}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('summary.cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete}>{t('summary.delete')}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
```

- [ ] **Step 6: Update `src/App.tsx`** — replace the SummaryPage import/routes:

```tsx
import { TransactionsPage } from './pages/TransactionsPage'
// remove: import { SummaryPage } ...

                <Route index element={<Navigate to="dashboard" replace />} />
                <Route path="dashboard" element={<DashboardPage />} />
                <Route path="transactions" element={<TransactionsPage />} />
                <Route path="summary" element={<Navigate to="/app/transactions" replace />} />
// and the catch-all:
            <Route path="*" element={<Navigate to="/app/dashboard" replace />} />
```

- [ ] **Step 7: Delete `src/pages/SummaryPage.tsx`**

```bash
rm src/pages/SummaryPage.tsx
```

- [ ] **Step 8: Gate + commit**

Run: `npm run build && npm test`
Expected: green.

```bash
git add -A
git commit -m "feat: day-grouped transactions page replacing summary"
```

### Task 13: Remove antd + final cleanup

**Files:**
- Modify: `src/main.tsx`, `src/i18n/I18nContext.tsx`, `src/test/setup.ts`, `package.json`, `CLAUDE.md`

- [ ] **Step 1: Rewrite `src/main.tsx`**

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Toaster } from '@/components/ui/sonner'
import App from './App'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
    <Toaster position="top-center" richColors />
  </StrictMode>,
)
```

- [ ] **Step 2: Replace the antd `Spin` in `src/i18n/I18nContext.tsx`** — remove the `import { Spin } from 'antd'` and swap the loading block for:

```tsx
  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-zinc-300 border-t-primary" aria-label="loading" />
      </div>
    )
  }
```

- [ ] **Step 3: Uninstall**

```bash
npm uninstall antd @ant-design/plots
grep -rn "from 'antd'\|@ant-design" src/   # expected: no matches
```

Update the comment above the `matchMedia` stub in `src/test/setup.ts` (no longer antd-specific — keep the stub, it is harmless and some libs still probe it).

- [ ] **Step 4: Update `CLAUDE.md`** (web repo) — Overview line: `Vite + React 19 + TypeScript + Tailwind v4 + shadcn/ui (vendored in src/components/ui/) + Recharts + sonner`. Architecture bullets: add `src/utils/paymentMethods.ts` to the comment-synced list, note pages are `/app/dashboard` + `/app/transactions` (`/app/summary` redirects), remove the antd-specific testing note and replace with: "Radix-based components may need ResizeObserver/scrollIntoView stubs in `src/test/setup.ts`".

- [ ] **Step 5: Full gate + commit**

Run: `npm run build && npm test && npm run lint`
Expected: all green, zero antd references.

```bash
git add -A
git commit -m "feat: drop antd; Tailwind-native app shell, toasts and spinner"
```

### Task 14: Full-stack verification (orchestrator repo)

**Files:** none (verification only; fix-forward anything found)

- [ ] **Step 1: Boot the stack**

Run (from the orchestrator repo): `docker compose up --build -d && docker compose ps`
Expected: `dmoney-postgres` healthy, `dmoney-api`, `dmoney-web` up.

- [ ] **Step 2: API round-trip with payment fields**

```bash
EMAIL="verify$(date +%s)@test.local"
curl -sf -X POST http://localhost:5113/users/register -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"username\":\"verify$(date +%s)\",\"password\":\"Passw0rd!123\",\"displayName\":\"Verify\"}"
TOKEN=$(curl -sf -X POST http://localhost:5113/users/login -H 'Content-Type: application/json' \
  -d "{\"identifier\":\"$EMAIL\",\"password\":\"Passw0rd!123\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -sf -X POST http://localhost:5113/transactions -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"date":"'"$(date +%Y-%m-%d)"'","content":"Netflix Premium","creditAmount":0,"debitAmount":260000,"note":null,"category":"entertainment","paymentMethod":"card","cardType":"visa","bank":"Techcombank"}'
curl -sf "http://localhost:5113/transactions?month=$(date +%Y-%m)" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep -E 'paymentMethod|cardType|bank'
```

Expected: create returns 201; GET shows `"paymentMethod": "card"`, `"cardType": "visa"`, `"bank": "Techcombank"`. (Adjust register/login field names to the actual endpoints in the be repo if they differ — check `src/Web.Api/Endpoints/Users/`.)

- [ ] **Step 3: Visual check vs mockup** — open http://localhost:8080, log in with the user above; compare Login, Dashboard, Transactions and the New-transaction dialog against `Money Track Designs (Standalone).html` opened in a browser (screens 2a–2d): topbar, 3 stat cards, green/red bars, day grouping, payment radio → card type → bank flow, `#6C4CF1` primary, Be Vietnam Pro font.

- [ ] **Step 4: Teardown + report**

Run: `docker compose down`
Report any mismatches; fix-forward in the owning repo and re-verify.

---

## Self-review notes

- Spec coverage: A→Tasks 1–3, B→Tasks 4–7, C→Tasks 8–13, verification→Task 14. Mockup deviations are restated in Global Constraints.
- Type consistency: `TransactionFormValues` produced in Task 10 is consumed verbatim in Tasks 11–12; `paymentLabel` created in Task 11 Step 6 before first use in the same task's page code; `toIncomeExpenseBars`/`groupTransactionsByDay` signatures match their tests.
- Backend record-position changes (Tasks 5) will surface every stale constructor via the zero-warnings build — fixing those call sites is in-scope for the task.
