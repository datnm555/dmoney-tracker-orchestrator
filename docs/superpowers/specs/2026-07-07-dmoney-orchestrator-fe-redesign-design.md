# dmoney-tracker: Orchestrator + Payment Method + FE Redesign (Tailwind/shadcn)

**Date:** 2026-07-07
**Status:** Approved
**Repos touched:** `dmoney-tracker-orchestrator` (A), `dmoney-tracker-be` (B), `dmoney-tracker-web` (C)

## Context

The system is 3 sibling repos under `dmoney-tracker/`:

- `dmoney-tracker-be` — .NET 10 API, Clean Architecture (SharedKernel ← Domain ← Application ← Infrastructure ← Web.Api), custom CQRS, EF Core + Postgres, i18n resx served at `GET /resources` (single translation source for BE errors AND all FE labels).
- `dmoney-tracker-web` — Vite + React 19 + TS, currently Ant Design 5 + @ant-design/plots. Pages: Login, Register, Dashboard, Summary.
- `dmoney-tracker-orchestrator` — this repo; currently only docker-compose (postgres + api + web) and the guide `HOW-TO-BUILD-AN-ORCHESTRATOR.md`.

The design mockup (`Money Track Designs (Standalone).html`, self-unpacking bundle) specifies 4 screens — 2a Login, 2b Dashboard, 2c New-transaction Dialog, 2d Transactions — and its own target stack: **Vite + React + Tailwind + shadcn/ui, primary `#6C4CF1`, zinc neutrals, radius 8px, font Be Vietnam Pro**, bilingual VI/EN.

## Decisions (user-approved)

1. FE stack: **Tailwind v4 + shadcn/ui**, antd fully removed.
2. Charts: **Recharts** (replaces @ant-design/plots).
3. Orchestrator: full per the guide, **Claude-first** (no Copilot `.github/instructions` layer yet; `AGENTS.md` included).
4. Payment method: **extend the BE** (domain + migration + DTOs), not an FE-only hack.
5. Pages: **3 screens per mockup** — Tổng quan (Dashboard), Giao dịch (new Transactions page replacing SummaryPage), Login/Register restyled. Nav shows Báo cáo / Cài đặt as disabled placeholders.

## Non-goals

- No Copilot/Codex adapter layer (can be generated later from the same skill source).
- No Báo cáo / Cài đặt pages.
- No dark mode.
- No multi-currency work beyond what exists (Money is VND-only today; the dialog's currency select renders the existing currency).

## A. Orchestrator repo

Keep the existing **sibling convention** (repos live next to each other under `dmoney-tracker/`; docker-compose already references `../dmoney-tracker-be`). The guide's `make clone-all` therefore clones into the **parent directory**, not into the orchestrator.

```
dmoney-tracker-orchestrator/
├── CLAUDE.md                      # thin: golden rules + pointer to routing table
├── AGENTS.md                      # generic-agent backbone → points at .claude/skills + routing
├── Makefile                       # clone-all / pull-all / status / branches / list (idempotent, guards)
├── agent_docs/
│   └── skill-routing.md           # topic→skill and directory→skill tables
├── .claude/skills/
│   ├── dmoney-platform/SKILL.md   # bird's-eye map (see below)
│   ├── dmoney-backend/SKILL.md    # distilled from be CLAUDE.md
│   └── dmoney-web/SKILL.md        # distilled from web CLAUDE.md (post-redesign stack)
├── docker-compose.yml             # unchanged
├── HOW-TO-BUILD-AN-ORCHESTRATOR.md
└── README.md                      # onboarding: layout, make targets, docker compose, skills
```

Skill content rules:

- Each SKILL.md has a trigger-rich `description` frontmatter ("Use this skill when… Triggers include '…', or working in the `<dir>/` directory.").
- Skills hold "enough to start" (overview table, quick commands, key rules/gotchas, related skills) and **link** to the source repo's `CLAUDE.md` for depth — one fact lives in one place (be/web CLAUDE.md stay the source of truth for per-repo detail).
- `dmoney-platform` holds: ASCII architecture diagram (web → api → postgres), repo classification (one line each + owning skill), dependency/contract map (types.ts ↔ DTOs, categories.ts ↔ TransactionCategories.cs, resx = all FE labels, ports 5173/5113/5432/8080), docker-compose quick reference, skill navigation guide.
- `CLAUDE.md` (orchestrator): golden rule "code changes happen in the real repos, never treat siblings as scratch"; always load the matching skill before answering; pointer to `agent_docs/skill-routing.md`.
- Makefile targets guard with `if [ -d ../<repo> ]` so re-runs are safe; repo list variable `REPOS = dmoney-tracker-be dmoney-tracker-web`; remote base `git@github.com:datnm555/`.

## B. Backend — payment method

Domain model (on `Transaction`):

- `PaymentMethod` enum: `Transfer` (default for existing rows), `Cash`, `Card`.
- `CardType` enum, nullable: `Visa`, `Credit`. Required when method is `Card`, must be null otherwise (domain-validated, returns `Error` per existing `Result` pattern, stable codes e.g. `Transactions.CardTypeRequired`).
- `Bank` string, nullable, max length per existing constants pattern; only allowed when method is `Card`.

Changes ripple through the existing layers, following the repo's conventions exactly:

- Create/Update commands + handlers + validation; DTO `TransactionResponse` gains `paymentMethod`, `cardType`, `bank` (camelCased).
- EF mapping + migration `AddPaymentMethod` via `dotnet dotnet-ef migrations add AddPaymentMethod --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations`. Existing rows default to `Transfer`.
- resx keys (BOTH `SharedResource.vi.resx` and `.en.resx`) for all new labels: payment method, transfer/cash/card, card type, bank names UI labels, validation error descriptions.
- Tests: unit tests for domain validation + handlers (MockQueryable.NSubstitute), integration tests for create/update round-trip with payment fields (Testcontainers). Gate: `dotnet build DMoney.slnx` zero warnings, `dotnet test DMoney.slnx`.

## C. Frontend — Tailwind + shadcn/ui redesign

Dependency swap:

- Remove: `antd`, `@ant-design/plots`.
- Add: `tailwindcss` v4 + `@tailwindcss/vite`, shadcn/ui components (vendored per shadcn model: Button, Input, Label, Card, Dialog, Tabs, Select, RadioGroup, Badge, Table, DropdownMenu, Separator), `recharts`, `lucide-react`, plus shadcn utilities (`clsx`, `tailwind-merge`, `class-variance-authority`, `@radix-ui/*` as pulled in by those components).
- Theme via CSS variables in `src/index.css`: primary `#6C4CF1` (hover `#4F35C9`), zinc neutral scale, `--radius: 8px`, income green `#16a34a`, expense red `#dc2626`. Font Be Vietnam Pro via Google Fonts in `index.html`.

Screens (match mockup):

- **AppLayout**: top bar — ₫ logo + "MoneyTrack", nav links Tổng quan / Giao dịch (+ Báo cáo, Cài đặt disabled), breadcrumb, VI/EN switch, user dropdown (name/email/logout).
- **Login (2a)** and **Register**: centered shadcn Card, ₫ logo, inputs + primary button, cross-links.
- **Dashboard "Tổng quan" (2b)**: greeting + date row, month tabs + currency select + "＋ Giao dịch mới" button; 3 stat cards (Số dư tổng, Ghi có, Ghi nợ) with deltas; Recharts grouped bar chart "Thu/Chi 6 tháng" fed by existing `/stats` monthly data via pure transforms in `src/utils/chartData.ts`; "Giao dịch gần đây" table (Giao dịch / Hình thức / Số tiền) + "Xem tất cả" link.
- **Transactions "Giao dịch" (2d)** — new page replacing SummaryPage: header with date-range + count, filter tabs Tất cả / Ghi có / Ghi nợ, month picker, month totals; transaction list grouped by day with day subtotals; each row: title, time · category, payment method badge, signed colored amount. Edit/delete preserved from current Summary behavior.
- **TransactionFormModal → shadcn Dialog (2c)**: Ghi nợ/Ghi có toggle (RadioGroup styled as segmented), Tiêu đề, Số tiền + currency select, category chips + "＋ Thêm" (existing custom-category behavior), Hình thức thanh toán radio cards (Chuyển khoản / Tiền mặt / Thẻ); selecting Thẻ reveals Loại thẻ (VISA / Credit) and Ngân hàng picker (Techcombank / VPBank / Khác → free text). Hủy / Lưu giao dịch footer.

Kept as-is: `api/client.ts` (axios, interceptors, STORAGE_KEYS), AuthContext/ProtectedRoute, I18nContext (`/resources`-driven, `t()` fallback), category sync contract. Routes: `/app/dashboard`, `/app/transactions`; `/app/summary` redirects to `/app/transactions`; default lands on dashboard. `src/api/types.ts` gains the three new fields.

Tests: vitest suites updated for new components (no more antd `matchMedia` needs, keep the stub harmless); TransactionFormModal tests rewritten for Dialog incl. card-type conditional; chartData transforms re-pointed at Recharts shapes. Dockerfile/nginx unchanged (`VITE_API_URL` build arg still used).

## Order & verification

**A → B → C.** A first so later sessions auto-load skills; B before C because the FE renders the new fields.

Final verification: `docker compose up --build` from the orchestrator → register/login → create transactions with each payment method (incl. Thẻ/Visa/Techcombank) → verify Dashboard cards/chart/table and Transactions grouping/filters render per mockup; side-by-side visual check against the standalone HTML rendered in a browser. Per-repo gates: `dotnet build` (zero-warning) + `dotnet test`; `npm run build` (tsc) + `npm test`.

## Risks / notes

- The mockup's currency select shows ₫ VND only — Money is VND-only server-side; the select is display-only for now.
- resx keys are silently-falling-back (`t()` returns the raw key) — missing keys won't fail tests; the FE work must land the BE resx keys first (enforced by doing B before C).
- Bank list is a UI convenience (Techcombank/VPBank/Khác); BE stores a free-form string, so no bank enum to keep in sync.
