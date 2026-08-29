# dmoney-tracker: Gold tracking (Vàng) — quantity held, per type, from transactions

**Date:** 2026-08-29
**Status:** Approved
**Repos:** `dmoney-tracker-be` (branch `feature/gold` off `feature/beneficiaries`), `dmoney-tracker-web` (branch `feature/gold` off `feature/beneficiaries`) — feature branches stack; `main` still sits at the initial import in both repos.

## Decisions (user-approved)

1. The user buys (and may sell) physical gold and wants to see **how much gold
   they hold** — total chỉ per gold type, each purchase's price, and the
   weighted-average cost per chỉ. Market price and profit/loss are **out of
   scope** for this phase.
2. **Gold types are user-defined** ("SJC miếng", "Nhẫn trơn 9999"…), per-user,
   shared across all plans — same shape as beneficiaries but with **no
   default** (nothing is pre-selected on the form).
3. **Both directions**: money-out + quantity = buy; money-in + quantity = sell.
   Held quantity = total bought − total sold.
4. **Attached to transactions** (no separate gold ledger): a transaction gains
   an optional pair `goldTypeId` + `goldQuantity`. Money stays single-source-
   of-truth in transactions — no double entry, no drift.
5. Holdings are **user-level across all plans (sổ)** — the gold you hold does
   not depend on which ledger recorded it. The gold summary API therefore takes
   **no `planId`** (deliberate exception to the "planId on all transaction
   APIs" contract; it is a gold API, not a transaction API).
6. Unit is **chỉ** (decimal, fractions like 0.5 allowed; 1 lượng = 10 chỉ is a
   display concern for a later phase).

## Backend (`dmoney-tracker-be`)

- `Domain/GoldTypes/GoldType.cs`: `Id`, `UserId`, `Name` (required, trimmed,
  ≤ 100, unique per user); `Create`, `Rename`. `GoldTypeErrors`:
  `NameRequired`, `NameTooLong`, `Duplicate`, `NotFound`, `InUse`.
- No seeding — the user creates their own list in Settings.
- Endpoints (all `RequireAuthorization`, CQRS like Plans/Beneficiaries):
  `GET /gold-types` (ordered by name) · `POST /gold-types {name}` ·
  `PUT /gold-types/{id} {name}` · `DELETE /gold-types/{id}` (referenced by any
  transaction → 409 `GoldTypes.InUse`). No set-default endpoint.
- `Transaction` gains `GoldTypeId` (Guid?, FK Restrict) and `GoldQuantity`
  (decimal(18,4)?, chỉ). Migration without backfill. Create/Update validation:
  - both present or both absent → else 400 `Transactions.GoldPairRequired`;
  - `GoldQuantity > 0` → else 400 `Transactions.GoldQuantityInvalid`;
  - gold type must exist and belong to the user → else 404 `GoldTypes.NotFound`.
  Allowed on debit (buy) and credit (sell) alike.
- `GET /gold/summary` (new, no query params): one payload for the Gold page —
  - `types[]`: per gold type — `goldTypeId`, `name`, `heldQuantity`
    (bought − sold), `boughtQuantity`, `soldQuantity`, `totalSpent` (sum of
    debit amounts), `totalReceived` (sum of credit amounts),
    `averageCostPerChi` (`totalSpent / boughtQuantity`, 0 when nothing bought);
  - `transactions[]`: every gold transaction all-time, date desc —
    `transactionId`, `date`, `content`, `goldTypeId`, `goldTypeName`,
    `goldQuantity`, `credit`, `debit`, `pricePerChi` (amount ÷ quantity).
  Types the user created but never traded still appear with zeros.
- `TransactionResponse` gains `goldTypeId`, `goldTypeName` (projected like
  `beneficiaryName`) and `goldQuantity`.
- resx vi/en: `menu.gold` ("Vàng"/"Gold"), `gold.*` labels (title, types,
  create, name, rename, delete, deleteConfirm, held, bought, sold, avgCost,
  totalSpent, totalReceived, history, unit "chỉ", empty),
  `form.goldToggle`, `form.goldType`, `form.goldQuantity`,
  `export.colGoldType`, `export.colGoldQuantity` + descriptions for the new
  error codes.

## Frontend (`dmoney-tracker-web`)

- `src/api/goldApi.ts` (gold-type CRUD + `getGoldSummary`) +
  `GoldTypeResponse { id, name }`, `GoldSummaryResponse` in `src/api/types.ts`;
  `TransactionResponse` gains `goldTypeId`/`goldTypeName`/`goldQuantity`;
  `TransactionPayload` gains `goldTypeId: string | null`,
  `goldQuantity: number | null`.
- `src/gold/GoldTypesContext.tsx` (pattern: BeneficiariesContext):
  `goldTypes`, `refresh` — consumed by form, settings page and Gold page.
- Settings page `/app/settings/gold-types` (pattern: beneficiaries settings
  minus the default button): list, create, inline rename, delete (surface
  `InUse` error toast).
- TransactionFormModal: a "Giao dịch vàng" toggle (both in and out types).
  Off (default) → fields hidden, submits nulls. On → Select "Loại vàng" +
  numeric input "Số chỉ" (step 0.1), both required while on; edit mode opens
  with the toggle on when the stored transaction has gold fields. Turning the
  toggle off clears both.
- New page **Vàng** `/app/gold` (menu item "Vàng"): summary cards per gold
  type — held chỉ, average cost per chỉ, total spent / received — and a
  history table below (date, content, type, chỉ, amount, price per chỉ,
  buy/sell direction). Data from `GET /gold/summary` on load.
- TransactionsPage: rows with gold render a chip "🪙 {quantity} chỉ ·
  {typeName}" next to the category chip. Excel export gains "Loại vàng" and
  "Số chỉ" columns.
- Import: rows carry no gold fields (out of scope to map them).

## Verification

BE: integration tests — gold-type CRUD + name ordering + per-user uniqueness;
delete blocked while referenced (`InUse`) and allowed after unlink; gold pair
validation (type without quantity, quantity without type, quantity ≤ 0);
foreign/unknown gold type → 404; summary math for mixed buys/sells across
plans (held, avg cost, zero-trade type shows zeros); response carries the new
fields; update path threads the new fields through the explicit PUT DTO
(per the update-endpoint memory). Gates: `dotnet build` + `dotnet test`.
FE: vitest — form toggle shows/requires/clears the pair and pre-fills on edit;
settings page CRUD; Gold page renders per-type aggregates and history from a
mocked summary. Gates: `npm test && npm run build && npm run lint`.
Final: docker E2E against the live stack, then **delete all E2E test data**
(users, gold types, categories) per the cleanup memory.

## Cross-repo contract additions

Add to the dmoney-platform skill contract table (this repo, same piece of
work): Gold type DTO + optional `goldTypeId`/`goldQuantity` pair on
transaction writes and `goldTypeId`/`goldTypeName`/`goldQuantity` on reads —
backend `src/Application/GoldTypes/Data/GoldTypeResponse.cs` /
`src/Application/Gold/Data/GoldSummaryResponse.cs`, frontend
`src/api/types.ts`, `src/api/goldApi.ts`, `src/gold/`.

## Out of scope (later phases)

Market gold price + profit/loss, dashboard charts, import-column mapping,
lượng/cây display conversion, per-plan gold breakdown.
