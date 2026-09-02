# Gold Acquisitions (Vàng có sẵn) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can record pre-owned/gifted gold (quantity + unit price at the time, no money flow) so holdings, total spent and average cost merge both sources on the Gold page.

**Architecture:** New `GoldAcquisition` aggregate (own CRUD slice under `/gold/acquisitions`), merged into the `GET /gold/summary` math and response; FE adds a create/edit dialog and merges acquisition rows into the Gold page history with a "Có sẵn" badge. No transaction-model or transaction-UI changes.

**Tech Stack:** same as gold v1 — .NET 10 Clean Architecture + custom CQRS + EF Core/Npgsql, xUnit/Shouldly/Testcontainers; Vite + React 19 + TS + shadcn, vitest.

**Spec:** `docs/superpowers/specs/2026-09-02-gold-acquisitions-design.md` (orchestrator repo). Gold v1 patterns: `docs/superpowers/specs/2026-08-29-gold-tracking-design.md`.

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`; continue on the EXISTING `feature/gold` branches (open PRs be#11/web#8 absorb the commits). Never commit code in the orchestrator repo. Pull/verify branch state first; push after each completed BE/FE phase.
- `GoldAcquisition`: `Date` required; `Quantity > 0` → else `GoldAcquisitions.QuantityInvalid` (400); `UnitPrice >= 0` → else `GoldAcquisitions.UnitPriceInvalid` (400); `Note` trimmed nullable ≤ 255 (`GoldAcquisitionConstants.NoteMaxLength = 255`) → else `GoldAcquisitions.NoteTooLong`; unknown/foreign id → `GoldAcquisitions.NotFound` (404); unknown/foreign gold type on create/update → `GoldTypes.NotFound` (404).
- EF: table `gold_acquisitions`, FK users Cascade, FK gold_types **Restrict**, `HasIndex(UserId)`, `Quantity numeric(18,4)`, `UnitPrice numeric(18,2)`. Migration `AddGoldAcquisitions` via `dotnet dotnet-ef migrations add AddGoldAcquisitions --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations`, scaffold untouched.
- Summary merge math (spec §3): `BoughtQuantity` = tx buys + acq qty; `TotalSpent` = tx buy amounts + Σ(qty × unitPrice); `HeldQuantity` = merged bought − sold; `AverageCostPerChi = Math.Round(spent/bought, 2)` (0 when bought = 0); `Value = Math.Round(qty × unitPrice, 0)`.
- Gold-type delete `InUse` guard covers transactions OR acquisitions.
- Handlers `internal sealed`, `*CommandHandler`/`*QueryHandler`, explicit DI registration (architecture tests enforce).
- resx: both `SharedResource.vi.resx` + `.en.resx`, identical keys/order — the exact 12 `goldAcq.*`/`GoldAcquisitions.*` lines are in the spec §Backend, copy verbatim.
- BE gates: `dotnet build && dotnet test` (Docker needed). FE gates: `npm test && npm run build && npm run lint` (no NEW warnings).
- E2E finishes with mandatory test-data cleanup (memory) and a stack rebuild/redeploy.

---

### Task 1: BE — GoldAcquisition entity, table, CRUD endpoints

**Files:**
- Create: `src/Domain/GoldAcquisitions/{GoldAcquisition,GoldAcquisitionConstants,GoldAcquisitionErrors}.cs`
- Create: `src/Infrastructure/GoldAcquisitions/GoldAcquisitionConfiguration.cs`
- Create: `src/Application/GoldAcquisitions/{GoldAcquisitionCommands.cs,CreateGoldAcquisitionCommandHandler.cs,UpdateGoldAcquisitionCommandHandler.cs,DeleteGoldAcquisitionCommandHandler.cs,GetGoldAcquisitionsQuery.cs,GetGoldAcquisitionsQueryHandler.cs,Data/GoldAcquisitionResponse.cs}` — the summary (Task 2) reuses the response record via `using Application.GoldAcquisitions.Data;`.
- Create: `src/Web.Api/Endpoints/GoldAcquisitions/GoldAcquisitionEndpoints.cs`
- Create: migration `AddGoldAcquisitions`
- Modify: `src/Application/Abstractions/Data/IApplicationDbContext.cs`, `src/Infrastructure/Database/ApplicationDbContext.cs` (+`DbSet<GoldAcquisition> GoldAcquisitions`), `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/GoldAcquisitions/GoldAcquisitionsEndpointsTests.cs`

**Interfaces:**
- Produces: `GoldAcquisition.Create(Guid userId, Guid goldTypeId, DateOnly date, decimal quantity, decimal unitPrice, string? note)` and instance `Update(Guid goldTypeId, DateOnly date, decimal quantity, decimal unitPrice, string? note)` (both `Result`-returning with the Global-Constraints validations); records `CreateGoldAcquisitionCommand(Guid GoldTypeId, DateOnly Date, decimal Quantity, decimal UnitPrice, string? Note) : ICommand<Guid>`, `UpdateGoldAcquisitionCommand(Guid Id, Guid GoldTypeId, DateOnly Date, decimal Quantity, decimal UnitPrice, string? Note) : ICommand`, `DeleteGoldAcquisitionCommand(Guid Id) : ICommand`, `GetGoldAcquisitionsQuery : IQuery<List<GoldAcquisitionResponse>>`; `GoldAcquisitionResponse(Guid Id, DateOnly Date, Guid GoldTypeId, string GoldTypeName, decimal Quantity, MoneyResponse UnitPrice, MoneyResponse Value, string? Note)` (uses `Application.Transactions.Data.MoneyResponse`); routes `GET/POST /gold/acquisitions`, `PUT/DELETE /gold/acquisitions/{id:guid}`; `dbContext.GoldAcquisitions`.

- [ ] **Step 1: Branch check** — `cd ../dmoney-tracker-be && git checkout feature/gold && git pull` (expect HEAD 3fbe55f or later, clean).
- [ ] **Step 2: Failing integration tests** — new file mirroring `GoldTypes/GoldTypesEndpointsTests.cs` (copy its `CreateAuthenticatedClientAsync`, `LoginBody`, `CreatedBody`, `CreateGoldTypeAsync` helpers; add `MoneyBody(decimal Amount, string Currency)` and `internal sealed record AcquisitionBody(Guid Id, string Date, Guid GoldTypeId, string GoldTypeName, decimal Quantity, MoneyBody UnitPrice, MoneyBody Value, string? Note);`). Facts:
  1. `GetAcquisitions_WithoutToken_Returns401`.
  2. `CreateListUpdateDelete_Works` — create type "Nhẫn cũ"; POST acquisition `{goldTypeId, date = "2024-05-10", quantity = 3m, unitPrice = 5_500_000m, note = "mua 2024"}` → 201; POST gift `{... quantity = 2m, unitPrice = 0m, note = "được tặng"}` → 201; GET list → 2 rows date-desc, first row `Value.Amount == 0m`, second `Value.Amount == 16_500_000m`, `GoldTypeName == "Nhẫn cũ"`; PUT first `{...quantity = 2.5m, unitPrice = 5_600_000m...}` → 204 and list reflects `Value.Amount == 14_000_000m`; DELETE → 204 and list count 1.
  3. `Validation_Works` — quantity 0 → 400; unitPrice −1 → 400; note 256 chars → 400; unknown goldTypeId → 404; foreign user's acquisition PUT/DELETE → 404.
- [ ] **Step 3: Verify FAIL** (404s): `dotnet test --filter GoldAcquisitionsEndpointsTests`.
- [ ] **Step 4: Implement** — domain mirrors `GoldType.cs` shape (AuditedEntity, private ctor, static Create + instance Update, `Guid.CreateVersion7()`); validations per Global Constraints; `Value` is NOT stored — computed in projections. Configuration mirrors `GoldTypeConfiguration` + the two FKs and column types from Global Constraints. Handlers mirror the GoldTypes slice (auth check → for create/update: gold-type ownership check → domain → save); the list handler projects date desc, then CreatedAt desc:

```csharp
        return await dbContext.GoldAcquisitions
            .Where(a => a.UserId == userId)
            .OrderByDescending(a => a.Date)
            .ThenByDescending(a => a.CreatedAt)
            .Select(a => new GoldAcquisitionResponse(
                a.Id,
                a.Date,
                a.GoldTypeId,
                dbContext.GoldTypes.Where(g => g.Id == a.GoldTypeId).Select(g => g.Name).First(),
                a.Quantity,
                new MoneyResponse(a.UnitPrice, Money.DefaultCurrency),
                new MoneyResponse(Math.Round(a.Quantity * a.UnitPrice, 0), Money.DefaultCurrency),
                a.Note))
            .ToListAsync(cancellationToken);
```

  Endpoints file mirrors `GoldTypeEndpoints.cs` (4 IEndpoint classes; POST binds `CreateGoldAcquisitionCommand` directly; PUT uses a nested `UpdateGoldAcquisitionRequest(Guid GoldTypeId, DateOnly Date, decimal Quantity, decimal UnitPrice, string? Note)` record threaded into the command with the route id). Register the 4 handlers in `DependencyInjection.cs`.
- [ ] **Step 5: Migration** — per Global Constraints; then **Step 6:** `dotnet build && dotnet test` PASS; **Step 7:** commit `feat: gold acquisitions entity and crud endpoints`.

---

### Task 2: BE — summary merge + gold-type delete guard

**Files:**
- Modify: `src/Application/Gold/Data/GoldSummaryResponse.cs`, `src/Application/Gold/GetGoldSummaryQueryHandler.cs`, `src/Application/GoldTypes/DeleteGoldTypeCommandHandler.cs`
- Test: `tests/Api.IntegrationTests/Gold/GoldSummaryEndpointTests.cs`, `tests/Api.IntegrationTests/GoldTypes/GoldTypesEndpointsTests.cs`

**Interfaces:**
- Consumes: Task 1 (`dbContext.GoldAcquisitions`, `GoldAcquisitionResponse`).
- Produces: `GoldSummaryResponse(IReadOnlyList<GoldTypeSummaryResponse> Types, IReadOnlyList<GoldTransactionResponse> Transactions, IReadOnlyList<GoldAcquisitionResponse> Acquisitions)`; per-type math per Global Constraints (merged bought/spent/avg).

- [ ] **Step 1: Failing tests** —
  - `GoldSummaryEndpointTests`: add `Acquisitions` list to `GoldSummaryBody` (reuse `AcquisitionBody` shape from Task 1's test file, duplicated per convention). New fact `GoldSummary_MergesAcquisitions`: type "Nhẫn merge" — tx buy 2 chỉ / 20M (default plan), acquisition 3 chỉ @ 5,000,000 (15M), gift acquisition 1 chỉ @ 0, tx sell 1 chỉ / 12M. Expect: bought 6, sold 1, held 5, spent 35M, received 12M, avgCost `Math.Round(35_000_000m/6m, 2)`; `Acquisitions.Count == 2`.
  - `GoldTypesEndpointsTests`: new fact `Delete_BlockedByAcquisition_ThenAllowed` — create type, add acquisition → DELETE type → 409; delete acquisition → DELETE type → 204.
- [ ] **Step 2: FAIL**, **Step 3: Implement** —
  - Handler: after the existing per-type tx aggregate `rows`, add an acquisitions aggregate and fold it into the per-type mapping:

```csharp
        var acqRows = await dbContext.GoldAcquisitions
            .Where(a => a.UserId == userId)
            .GroupBy(a => a.GoldTypeId)
            .Select(g => new
            {
                GoldTypeId = g.Key,
                Quantity = g.Sum(a => a.Quantity),
                Cost = g.Sum(a => a.Quantity * a.UnitPrice)
            })
            .ToListAsync(cancellationToken);
```

    In the per-type projection: `decimal acqQty = acqRows.FirstOrDefault(r => r.GoldTypeId == type.Id)?.Quantity ?? 0m;` and `acqCost` likewise; then `bought = txBought + acqQty`, `spent = txSpent + acqCost`, `held = bought - sold`, avg per Global Constraints. Reuse the Task 1 list-projection block (same Select) to fill `Acquisitions` — either by invoking the same query inline or duplicating the Select (duplication matches this codebase's per-slice convention; note it in the report either way).
  - `DeleteGoldTypeCommandHandler`: extend the guard —

```csharp
        bool inUse = await dbContext.Transactions.AnyAsync(
            t => t.GoldTypeId == goldType.Id, cancellationToken)
            || await dbContext.GoldAcquisitions.AnyAsync(
                a => a.GoldTypeId == goldType.Id, cancellationToken);
```

- [ ] **Step 4: PASS** (`dotnet build && dotnet test`), **Step 5:** commit `feat: merge gold acquisitions into summary and delete guard`.

---

### Task 3: BE — resx keys, push

**Files:** `src/Web.Api/Resources/SharedResource.{vi,en}.resx`

- [ ] Add the 12 keys per file EXACTLY as listed in the spec §Backend resx block (4 error codes after `Transactions.GoldRequiresAmount`; 8 `goldAcq.*` UI keys after the `form.goldQuantityRequired` block), identical order both files. Gates `dotnet build && dotnet test`; commit `feat: gold acquisition resx keys (vi/en)`; `git push origin feature/gold`.

---

### Task 4: FE — types, api, dialog

**Files:**
- Create: `src/gold/GoldAcquisitionDialog.tsx`
- Modify: `src/api/types.ts`, `src/api/goldApi.ts`
- Test: `src/gold/GoldAcquisitionDialog.test.tsx`

**Interfaces:**
- Produces: `GoldAcquisitionResponse { id, date, goldTypeId, goldTypeName, quantity, unitPrice: MoneyResponse, value: MoneyResponse, note: string | null }`; `GoldSummaryResponse` gains `acquisitions: GoldAcquisitionResponse[]`; `GoldAcquisitionPayload { goldTypeId: string, date: string, quantity: number, unitPrice: number, note: string | null }`; `createGoldAcquisition(payload)`, `updateGoldAcquisition(id, payload)`, `deleteGoldAcquisition(id)`; `<GoldAcquisitionDialog open editing={GoldAcquisitionResponse | null} onClose onSaved />` — create mode when `editing` is null, edit mode pre-fills and calls update.

- [ ] **Step 1: Branch check** — `cd ../dmoney-tracker-web && git checkout feature/gold && git pull` (HEAD 71c1a7a or later, clean).
- [ ] **Step 2: Failing tests** — mock `../api/goldApi`, `./GoldTypesContext` (`goldTypes: [{id: 'g-1', name: 'Nhẫn trơn'}]`), i18n (t→key). Tests: (1) create mode: pick type, type date `2024-05-10`, quantity `3`, unit price `5500000` (typed as digits), note, submit → `createGoldAcquisition` called with `{goldTypeId: 'g-1', date: '2024-05-10', quantity: 3, unitPrice: 5500000, note: 'mua 2024'}` and `onSaved` invoked; (2) missing type or quantity → submit blocked, api not called; (3) edit mode with an editing fixture → fields pre-filled, submit calls `updateGoldAcquisition(id, ...)`.
- [ ] **Step 3: Implement** — dialog mirrors `CreateGoldTypeDialog.tsx` structure (Dialog/DialogContent/Footer, saving state, `getApiErrorMessage` toast). Fields: Select gold type (pattern: form modal's gold select, `'none'` sentinel); date `<Input type="date">` defaulting `dayjs().format('YYYY-MM-DD')`; quantity decimal input (pattern: form modal's gold quantity — `inputMode="decimal"`, `/[^\d.,]/g`, parse `Number(text.replace(',', '.'))`, must be > 0); unit price VND input (pattern: form modal's amount — digits-only + `formatThousands` display, `Number(digits || '0')`, ≥ 0 allowed incl. 0 for gifts); note `<Input>`. Labels: `goldAcq.date/quantity/unitPrice/note`, title `goldAcq.add`/`goldAcq.edit`, submit `summary.submit` or reuse `goldAcq.add` — use `t('summary.submit')` if that key exists in the codebase (check TransactionFormModal), else `t('goldAcq.add')`. Hydration on open: editing → prefill (unitPrice digits = `String(editing.unitPrice.amount)`), else reset.
- [ ] **Step 4: Gates + commit** — `feat: gold acquisition dialog and api`.

---

### Task 5: FE — Gold page merge (badge rows, edit/delete)

**Files:**
- Modify: `src/pages/GoldPage.tsx`
- Test: `src/pages/GoldPage.test.tsx`

**Interfaces:**
- Consumes: Task 4 dialog + api + types.

- [ ] **Step 1: Failing tests** — extend the mocked summary with `acquisitions: [{id: 'acq-1', date: '2024-05-10', goldTypeId: 'g-1', goldTypeName: 'Nhẫn trơn', quantity: 3, unitPrice: {amount: 5500000, currency: 'VND'}, value: {amount: 16500000, currency: 'VND'}, note: 'mua 2024'}]` (and `acquisitions: []` in the empty-state override). Tests: (1) history renders the acquisition row with badge `goldAcq.badge`, note text and its value; (2) clicking the row's delete button then the confirm calls `deleteGoldAcquisition('acq-1')` and refreshes (getGoldSummary called again); (3) the header button `goldAcq.add` opens the dialog (mock `../gold/GoldAcquisitionDialog` to a probe recording its `open`/`editing` props).
- [ ] **Step 2: Implement** —
  - Merge for the table: `const historyRows = [...transactions.map(tx => ({kind: 'tx' as const, date: tx.date, key: tx.transactionId, tx})), ...acquisitions.map(a => ({kind: 'acq' as const, date: a.date, key: a.id, acq: a}))].sort((x, y) => y.date.localeCompare(x.date))`.
  - Acquisition row cells: date; Badge `goldAcq.badge` + note (or '—'); goldTypeName; quantity via `formatGoldQuantity` + `gold.unit`; amount cell `formatMoney(value)` with `className="text-right text-muted-foreground"` (no sign/color); price cell `formatMoney(unitPrice)`; trailing actions cell with Pencil (open dialog with `editing`) and Trash2 (AlertDialog confirm → `deleteGoldAcquisition` → reload) icon buttons (pattern: GoldTypeSettingsPage row buttons). Transaction rows keep their current cells + an empty actions cell.
  - Header: `goldAcq.add` Button (Plus icon) beside the title; dialog state `{open, editing}`; `onSaved`/delete → `load()`.
  - Empty state colSpan becomes 7 (new actions column).
- [ ] **Step 3: Gates + commit + push** — `feat: pre-owned gold on the gold page`; `git push origin feature/gold`.

---

### Task 6: E2E, cleanup, deploy, docs

- [ ] **Step 1:** `docker compose up --build -d` (orchestrator repo); wait for api. E2E with a throwaway user: create type → 2 acquisitions (one gift price 0) + 1 tx buy + 1 tx sell → `GET /gold/summary` verifies merged math per spec §3 and the acquisitions array; PUT + DELETE an acquisition; gold-type delete blocked by acquisition (409) then allowed; validation 400/404 spot-checks. Web serves `/app/gold`.
- [ ] **Step 2: CLEANUP (mandatory):** delete the run's test users/gold data/categories via `docker exec dmoney-postgres psql`; verify zero `%example.com%` users remain.
- [ ] **Step 3:** Leave the freshly built stack running (this IS the redeploy). Update orchestrator `.claude/skills/dmoney-platform/SKILL.md` gold contract row (acquisitions endpoints + DTO + merged-math note); commit `docs: gold acquisitions contract in platform skill` + push main.
- [ ] **Step 4:** Confirm both `feature/gold` branches pushed — PRs be#11/web#8 update automatically; note the addition on each PR with `mcp__github__add_issue_comment` (gh CLI is the wrong account per memory).
