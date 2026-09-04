# Purchase Places (Nơi mua) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-user purchase-place catalog (Settings) selectable on both gold entry points (acquisition dialog + transaction gold block), displayed in the Gold page history.

**Architecture:** `PurchasePlace` aggregate mirroring the GoldTypes slice; nullable `PurchasePlaceId` FK (Restrict) on `transactions` and `gold_acquisitions` with a place-requires-gold guard on transactions; id+name projected into the three read contracts; FE clones the gold-types settings set and adds two optional Selects.

**Tech Stack:** unchanged (NET 10 CQRS/EF, React 19/vitest).

**Spec:** `docs/superpowers/specs/2026-09-03-purchase-places-design.md` (orchestrator repo) — the resx block and error codes there are verbatim requirements.

## Global Constraints

- Repos: BE `../dmoney-tracker-be` (HEAD 10a2aaf), FE `../dmoney-tracker-web` (HEAD 8de3739); continue on `feature/gold` (open PRs absorb commits). Never commit code in the orchestrator repo.
- Mirror slices are the law: PurchasePlace domain/config/application/endpoints/tests mirror the GoldTypes slice byte-for-byte with renames and no omissions; the two Selects mirror the existing gold-type Select pattern (`'none'` sentinel).
- Guards: place on a transaction without the gold pair → 400 `Transactions.PurchasePlaceRequiresGold`; unknown/foreign place → 404 `PurchasePlaces.NotFound`; delete place referenced by tx OR acquisition → 409 `PurchasePlaces.InUse`.
- BOTH explicit PUT request DTOs (`UpdateTransactionRequest`, `UpdateGoldAcquisitionRequest`) must hand-thread `PurchasePlaceId` with update-path tests (the transactions one is the historical failure mode).
- All appended record params trailing-optional (`Guid? PurchasePlaceId = null, string? PurchasePlaceName = null`); projections append positionally.
- Migrations via `dotnet dotnet-ef migrations add <Name> --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations`: `AddPurchasePlaces` (Task 1), `AddPurchasePlaceRefs` (Task 2). Scaffolds untouched.
- Handlers `internal sealed` + naming, explicit DI registration. resx keys verbatim from the spec, identical order in both files.
- BE gates: `dotnet build && dotnet test` (Docker). FE gates: `npm test && npm run build && npm run lint` (no NEW warnings). E2E ends with cleanup (memory), stack rebuild (deploy), docs + PR comments via MCP (gh CLI is the wrong account — memory).

---

### Task 1: BE — PurchasePlace slice (entity, table, full CRUD)

**Files:** Create `src/Domain/PurchasePlaces/{PurchasePlace,PurchasePlaceConstants,PurchasePlaceErrors}.cs`, `src/Infrastructure/PurchasePlaces/PurchasePlaceConfiguration.cs`, `src/Application/PurchasePlaces/{PurchasePlaceCommands.cs,CreatePurchasePlaceCommandHandler.cs,UpdatePurchasePlaceCommandHandler.cs,DeletePurchasePlaceCommandHandler.cs,GetPurchasePlacesQuery.cs,GetPurchasePlacesQueryHandler.cs,Data/PurchasePlaceResponse.cs}`, `src/Web.Api/Endpoints/PurchasePlaces/PurchasePlaceEndpoints.cs`, migration `AddPurchasePlaces`, test `tests/Api.IntegrationTests/PurchasePlaces/PurchasePlacesEndpointsTests.cs`; Modify `IApplicationDbContext`/`ApplicationDbContext` (+`DbSet<PurchasePlace> PurchasePlaces`), `DependencyInjection.cs`.

**Interfaces:** `PurchasePlace.Create(Guid userId, string name)`/`Rename`; `PurchasePlaceErrors.{NameRequired,NameTooLong,Duplicate,NotFound,InUse}`; `PurchasePlaceResponse(Guid Id, string Name)`; commands `CreatePurchasePlaceCommand(string Name):ICommand<Guid>`, `UpdatePurchasePlaceCommand(Guid Id, string Name):ICommand`, `DeletePurchasePlaceCommand(Guid Id):ICommand`; routes `GET/POST /purchase-places`, `PUT/DELETE /purchase-places/{id:guid}`.

- [x] TDD: new test file cloned from `GoldTypes/GoldTypesEndpointsTests.cs` structure — facts: 401 without token; create+list (name order, duplicate 409, blank 400); rename (204 + rename-onto-existing 409); delete unused 204 / foreign user 404. Verify FAIL (404s) → implement the mirror slice (delete has NO InUse guard yet — the referencing columns land in Task 2) → migration → `dotnet build && dotnet test` PASS → commit `feat: purchase place entity and crud endpoints`.

---

### Task 2: BE — PurchasePlaceId on transactions + acquisitions, projections, guards

**Files:** Modify `src/Domain/Transactions/{Transaction,TransactionErrors}.cs`, `src/Domain/GoldAcquisitions/GoldAcquisition.cs`, `src/Application/Transactions/{CreateTransactionCommand.cs+handler,UpdateTransactionCommand.cs+handler,Data/TransactionResponse.cs,GetTransactionsByMonthQueryHandler.cs}`, `src/Web.Api/Endpoints/Transactions/UpdateTransaction.cs`, `src/Application/GoldAcquisitions/{GoldAcquisitionCommands.cs,Create/Update handlers,Data/GoldAcquisitionResponse.cs,GetGoldAcquisitionsQueryHandler.cs}`, `src/Web.Api/Endpoints/GoldAcquisitions/GoldAcquisitionEndpoints.cs` (PUT request record), `src/Application/Gold/{Data/GoldSummaryResponse.cs (GoldTransactionResponse),GetGoldSummaryQueryHandler.cs}`, `src/Application/PurchasePlaces/DeletePurchasePlaceCommandHandler.cs` (add InUse guard), `src/Infrastructure/Transactions/TransactionConfiguration.cs` + `src/Infrastructure/GoldAcquisitions/GoldAcquisitionConfiguration.cs` (FK Restrict each), migration `AddPurchasePlaceRefs`; tests in `TransactionsEndpointsTests`, `GoldAcquisitionsEndpointsTests`, `GoldSummaryEndpointTests`, `PurchasePlacesEndpointsTests`.

**Interfaces:** `Transaction.Create/Update` + both transaction commands + `UpdateTransactionRequest` gain trailing `Guid? PurchasePlaceId = null`; domain guard (both Create/Update, after the gold guards):

```csharp
        if (purchasePlaceId is not null && goldTypeId is null)
        {
            return Result.Failure<Transaction>(TransactionErrors.PurchasePlaceRequiresGold);
        }
```

with `TransactionErrors.PurchasePlaceRequiresGold = Error.Validation("Transactions.PurchasePlaceRequiresGold", "A purchase place only applies to gold transactions.");`. `GoldAcquisition.Create/Update` + its commands + `UpdateGoldAcquisitionRequest` gain the same trailing param (no guard). Handler ownership checks (all four create/update handlers): `AnyAsync(p => p.Id == id && p.UserId == userId)` → `PurchasePlaceErrors.NotFound`. `TransactionResponse`, `GoldTransactionResponse`, `GoldAcquisitionResponse` append `Guid? PurchasePlaceId = null, string? PurchasePlaceName = null` (+ correlated `dbContext.PurchasePlaces...Name` subqueries in `GetTransactionsByMonthQueryHandler`, both acquisition projections, and the summary tx-history projection). Delete guard: `Transactions.Any || GoldAcquisitions.Any` on `PurchasePlaceId` → `InUse`.

- [x] TDD facts: tx round-trip with place (create → month summary shows placeId+Name); place without gold pair → 400; unknown place → 404; **update-path threading** for `PUT /transactions/{id}` AND `PUT /gold/acquisitions/{id}` (create without place → PUT with place → read back shows it); acquisition + summary projections carry place; `PurchasePlaces` delete: referenced by tx → 409, by acquisition → 409, after unlink → 204. Verify FAIL → implement → migration → gates PASS → commit `feat: purchase place on gold transactions and acquisitions`.

---

### Task 3: BE — resx keys, push

- [x] Add the 14 keys from the spec's resx block to BOTH `SharedResource.{vi,en}.resx`, identical order: 6 error codes (5 `PurchasePlaces.*` after the `GoldAcquisitions.*` block; `Transactions.PurchasePlaceRequiresGold` after `Transactions.GoldRequiresAmount`) + 8 UI keys (`menu.purchasePlaces`, `purchasePlaces.{title,create,name,rename,delete,deleteConfirm}`, `form.purchasePlace`) after the `goldAcq.*` block. Gates → commit `feat: purchase place resx keys (vi/en)` → `git push origin feature/gold`.

---

### Task 4: FE — api, context, settings page

**Files:** Create `src/api/purchasePlaceApi.ts`, `src/purchasePlaces/{PurchasePlacesContext.tsx,CreatePurchasePlaceDialog.tsx}`, `src/pages/PurchasePlaceSettingsPage.tsx` (+ tests for context and page); Modify `src/api/types.ts` (`PurchasePlaceResponse { id, name }`), `src/App.tsx` (route `settings/purchase-places`), `src/layouts/AppLayout.tsx` (`Store` icon import, SETTINGS_ITEMS entry `menu.purchasePlaces`, `PurchasePlacesProvider` inside `GoldTypesProvider`).

- [x] Branch check (`feature/gold`, pull). TDD: context test (load+refresh, clone of GoldTypesContext.test) and settings-page test (list/rename/delete, clone of GoldTypeSettingsPage.test with `purchasePlaces.*` keys + `updatePurchasePlace`/`deletePurchasePlace`). Implement as byte-mirror clones of the gold-types set (`usePurchasePlaces(): { purchasePlaces, refresh }`). Gates → commit `feat: purchase place settings page`.

---

### Task 5: FE — selects in both forms + history display, push

**Files:** Modify `src/gold/GoldAcquisitionDialog.tsx`, `src/components/TransactionFormModal.tsx`, `src/pages/TransactionsPage.tsx` (payload passthrough), `src/api/goldApi.ts` (`GoldAcquisitionPayload.purchasePlaceId: string | null`), `src/api/transactionApi.ts` (`TransactionPayload.purchasePlaceId: string | null`), `src/api/types.ts` (3 response interfaces gain `purchasePlaceId`/`purchasePlaceName`), `src/pages/GoldPage.tsx` (history: both row kinds render `{typeName}` + `{purchasePlaceName && <span className="text-xs text-muted-foreground"> · {row.purchasePlaceName}</span>}`), ALL TransactionResponse fixtures (+2 null fields — grep `goldTypeName: null`), GoldPage/GoldAcquisitionDialog/TransactionFormModal tests.

- [x] TDD: dialog submits `purchasePlaceId` when picked and null otherwise + edit prefills; form modal gold block gains the Select (mock `../purchasePlaces/PurchasePlacesContext`), submitted only while the gold toggle is on (turning it off clears place too), `TransactionFormValues.purchasePlaceId`; TransactionsPage payload passes it through; GoldPage history shows ` · SJC` on a fixture row. Implement (Select pattern = existing gold-type Select; place Select sits next to it inside the gold block; acquisition dialog adds it after the type Select). Gates → commit `feat: purchase place selects and history display` → `git push origin feature/gold`.

---

### Task 6: E2E, cleanup, deploy, docs

- [x] `docker compose up --build -d` (this is the redeploy; leave running). E2E throwaway user: create place ×2 + type; acquisition with place; tx buy with place; tx with place but NO gold → 400; unknown place → 404; summary + acquisitions show placeName on rows; PUT threading spot-check both endpoints; place delete 409 (referenced) → unlink → 204. CLEANUP per memory (verify 0 test users/categories left). Update platform-skill gold contract row (purchase places endpoints + fields); commit + push orchestrator main (Claude trailers). PR comments on be#11/web#8 via `mcp__github__add_issue_comment`. Report actual numbers.
