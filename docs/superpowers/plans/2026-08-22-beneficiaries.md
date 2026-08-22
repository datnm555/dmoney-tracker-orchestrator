# Beneficiaries (Đối tượng) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Debit transactions can carry an optional per-user "beneficiary" (Tôi/Vợ/Con/…) with a settable default, managed in Settings and filterable on the Transactions page.

**Architecture:** New `Beneficiary` aggregate mirroring the Plans vertical slice (incl. its set-default endpoint), nullable `Transaction.BeneficiaryId` with debit-only validation, `beneficiaryId`+`beneficiaryName` projected into `TransactionResponse`; FE adds a context, a settings page cloned from PlanSettingsPage, a type-aware form select and a client-side filter.

**Tech Stack:** .NET 10 Clean Architecture + custom CQRS + EF Core/Npgsql, xUnit/Shouldly/Testcontainers; Vite + React 19 + TS + shadcn, vitest.

**Spec:** `docs/superpowers/specs/2026-08-22-beneficiaries-design.md` (orchestrator repo).

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`; branch `feature/beneficiaries` off `feature/plans` in BOTH. Never commit code in the orchestrator repo.
- Handlers are registered EXPLICITLY in BE `src/Application/DependencyInjection.cs` (no assembly scanning).
- `BeneficiaryConstants.NameMaxLength = 100`; name required, trimmed, unique per user (`Beneficiaries.Duplicate`, Conflict).
- `Transaction.BeneficiaryId` is NULLABLE, FK `DeleteBehavior.Restrict`, NO backfill. Beneficiary allowed only when `DebitAmount > 0` → else `Transactions.BeneficiaryDebitOnly` (Validation/400). Unknown/foreign beneficiary → `Beneficiaries.NotFound` (404).
- Delete guard: beneficiary referenced by any transaction → `Beneficiaries.InUse` (Conflict/409). Deleting an unreferenced default is allowed (no default remains).
- resx: both `SharedResource.vi.resx` + `SharedResource.en.resx`, key = error code; UI keys listed in Task 4 verbatim.
- BE gates per task: `dotnet build && dotnet test`. FE gates: `npm test && npm run build && npm run lint` (no NEW lint warnings).
- After E2E against the docker stack: DELETE all test users and any beneficiaries/categories the run created (cleanup memory).
- EF migrations: local tool manifest (`dotnet ef` or `dotnet dotnet-ef` per BE CLAUDE.md), output `src/Infrastructure/Database/Migrations/`.

---

### Task 1: BE — Beneficiary entity, table, GET + POST

**Files:**
- Create: `src/Domain/Beneficiaries/Beneficiary.cs`, `BeneficiaryConstants.cs`, `BeneficiaryErrors.cs`
- Create: `src/Infrastructure/Beneficiaries/BeneficiaryConfiguration.cs`
- Create: `src/Application/Beneficiaries/Data/BeneficiaryResponse.cs`, `GetBeneficiariesQuery.cs`, `GetBeneficiariesQueryHandler.cs`, `BeneficiaryCommands.cs`, `CreateBeneficiaryCommandHandler.cs`
- Create: `src/Web.Api/Endpoints/Beneficiaries/BeneficiaryEndpoints.cs`
- Create: migration `AddBeneficiaries`
- Modify: `src/Application/Abstractions/Data/IApplicationDbContext.cs`, `src/Infrastructure/Database/ApplicationDbContext.cs`, `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/Beneficiaries/BeneficiariesEndpointsTests.cs`

**Interfaces:**
- Produces: `Beneficiary.Create(Guid userId, string name, bool isDefault = false)`, `Beneficiary.Rename(string)`, `Beneficiary.MakeDefault()`, `Beneficiary.ClearDefault()`; `BeneficiaryErrors.{NameRequired,NameTooLong,Duplicate,NotFound,InUse}`; `BeneficiaryResponse(Guid Id, string Name, bool IsDefault)`; `GET /beneficiaries` (default first, then name), `POST /beneficiaries {name}` → `201 {id}`; records `UpdateBeneficiaryCommand(Guid Id, string Name)`, `DeleteBeneficiaryCommand(Guid Id)`, `SetDefaultBeneficiaryCommand(Guid Id)` (handlers in Task 2); `dbContext.Beneficiaries`.

- [ ] **Step 1: Branch setup**

```bash
cd ../dmoney-tracker-be && git checkout feature/plans && git pull && git checkout -b feature/beneficiaries
```

- [ ] **Step 2: Failing integration tests** — new file, copy `CreateAuthenticatedClientAsync`/`LoginBody`/`CreatedBody` records from `tests/Api.IntegrationTests/Plans/PlansEndpointsTests.cs` (per-file duplication is that project's convention):

```csharp
    internal sealed record BeneficiaryBody(Guid Id, string Name, bool IsDefault);

    [Fact]
    public async Task GetBeneficiaries_WithoutToken_Returns401()
    {
        (await factory.CreateClient().GetAsync("/beneficiaries")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task CreateAndList_Works()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("ben-create@example.com", "bencreate");

        var create = await client.PostAsJsonAsync("/beneficiaries", new { name = "Tôi" });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);

        (await client.PostAsJsonAsync("/beneficiaries", new { name = "Vợ" })).StatusCode.ShouldBe(HttpStatusCode.Created);
        // Duplicate name (same user) is a conflict.
        (await client.PostAsJsonAsync("/beneficiaries", new { name = "Tôi" })).StatusCode.ShouldBe(HttpStatusCode.Conflict);
        // Empty name is a validation error.
        (await client.PostAsJsonAsync("/beneficiaries", new { name = " " })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        var list = await (await client.GetAsync("/beneficiaries")).Content.ReadFromJsonAsync<List<BeneficiaryBody>>();
        list!.Count.ShouldBe(2);
        list.Select(b => b.Name).ShouldBe(new[] { "Tôi", "Vợ" }); // no default yet → plain name order
        list.All(b => !b.IsDefault).ShouldBeTrue();
    }
```

- [ ] **Step 3: Run to verify FAIL** — `dotnet test --filter BeneficiariesEndpointsTests` → 404s.

- [ ] **Step 4: Domain** — mirror `src/Domain/Plans/{Plan,PlanConstants,PlanErrors}.cs` with Plan→Beneficiary renames, plus these deltas:
  - `BeneficiaryConstants`: only `NameMaxLength = 100` (no default-name literal).
  - `Beneficiary` also gets `MakeDefault()`/`ClearDefault()` (copy from the current `Plan.cs` — it has them since the set-default commit).
  - `BeneficiaryErrors`:

```csharp
using SharedKernel;

namespace Domain.Beneficiaries;

public static class BeneficiaryErrors
{
    public static readonly Error NameRequired = Error.Validation(
        "Beneficiaries.NameRequired", "Please enter a name for the person.");

    public static readonly Error NameTooLong = Error.Validation(
        "Beneficiaries.NameTooLong",
        $"Name must be at most {BeneficiaryConstants.NameMaxLength} characters.");

    public static readonly Error Duplicate = Error.Conflict(
        "Beneficiaries.Duplicate", "This person already exists.");

    public static readonly Error NotFound = Error.NotFound(
        "Beneficiaries.NotFound", "Person not found.");

    public static readonly Error InUse = Error.Conflict(
        "Beneficiaries.InUse", "This person is used by transactions and cannot be deleted.");
}
```

- [ ] **Step 5: EF + DbContext** — `BeneficiaryConfiguration` mirrors `src/Infrastructure/Plans/PlanConfiguration.cs` exactly (table `beneficiaries`, Name max length, `HasIndex(UserId)`, FK to `User` with Cascade, `Ignore(DomainEvents)`). Add `DbSet<Beneficiary> Beneficiaries` to both `IApplicationDbContext` and `ApplicationDbContext`.

- [ ] **Step 6: Application + endpoint** — mirror the Plans files:
  - `BeneficiaryResponse(Guid Id, string Name, bool IsDefault)`.
  - `GetBeneficiariesQuery` + handler = copy `GetPlansQueryHandler` (same ordering: `OrderByDescending(IsDefault).ThenBy(Name)`).
  - `BeneficiaryCommands.cs`: `CreateBeneficiaryCommand(string Name) : ICommand<Guid>`, `UpdateBeneficiaryCommand(Guid Id, string Name) : ICommand`, `DeleteBeneficiaryCommand(Guid Id) : ICommand`, `SetDefaultBeneficiaryCommand(Guid Id) : ICommand`.
  - `CreateBeneficiaryCommandHandler` = copy `CreatePlanCommandHandler` + duplicate check before Add (pattern: `CreateCategoryCommandHandler`):

```csharp
        bool duplicate = await dbContext.Beneficiaries.AnyAsync(
            b => b.UserId == userId && b.Name == beneficiary.Value.Name, cancellationToken);
        if (duplicate)
        {
            return Result.Failure<Guid>(BeneficiaryErrors.Duplicate);
        }
```

  - `BeneficiaryEndpoints.cs`: `GetBeneficiaries` + `CreateBeneficiary` classes mirroring `PlanEndpoints.cs` (`/beneficiaries` routes, `201` + Location).
  - Register both handlers in `DependencyInjection.cs` next to the Plans lines.

- [ ] **Step 7: Migration** — `dotnet ef migrations add AddBeneficiaries --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations` (adjust invocation per BE CLAUDE.md). No seed SQL, no hand edits (pure new table).

- [ ] **Step 8: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 9: Commit** — `git add -A && git commit -m "feat: beneficiary entity with list and create endpoints"`

---

### Task 2: BE — rename, guarded delete, set-default

**Files:**
- Create: `src/Application/Beneficiaries/UpdateBeneficiaryCommandHandler.cs`, `DeleteBeneficiaryCommandHandler.cs`, `SetDefaultBeneficiaryCommandHandler.cs`
- Modify: `src/Web.Api/Endpoints/Beneficiaries/BeneficiaryEndpoints.cs`, `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/Beneficiaries/BeneficiariesEndpointsTests.cs`

**Interfaces:**
- Consumes: Task 1 records + entity methods.
- Produces: `PUT /beneficiaries/{id} {name}` → 204; `PUT /beneficiaries/{id}/default` → 204 (swaps the single default); `DELETE /beneficiaries/{id}` → 204 | 409 `Beneficiaries.InUse` | 404.

- [ ] **Step 1: Failing tests** (append; helper `CreateBeneficiaryAsync` mirrors `CreatePlanAsync`):

```csharp
    private static async Task<Guid> CreateBeneficiaryAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/beneficiaries", new { name });
        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<CreatedBody>())!.Id;
    }

    [Fact]
    public async Task RenameAndSetDefault_Work()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("ben-def@example.com", "bendef");
        Guid me = await CreateBeneficiaryAsync(client, "Tôi");
        Guid wife = await CreateBeneficiaryAsync(client, "Vợ");

        (await client.PutAsJsonAsync($"/beneficiaries/{me}", new { name = "Bản thân" }))
            .StatusCode.ShouldBe(HttpStatusCode.NoContent);

        (await client.PutAsync($"/beneficiaries/{wife}/default", null)).StatusCode.ShouldBe(HttpStatusCode.NoContent);
        var list = await (await client.GetAsync("/beneficiaries")).Content.ReadFromJsonAsync<List<BeneficiaryBody>>();
        list![0].Id.ShouldBe(wife);               // default first
        list[0].IsDefault.ShouldBeTrue();
        list.Count(b => b.IsDefault).ShouldBe(1);

        // Default moves when set on another.
        (await client.PutAsync($"/beneficiaries/{me}/default", null)).StatusCode.ShouldBe(HttpStatusCode.NoContent);
        list = await (await client.GetAsync("/beneficiaries")).Content.ReadFromJsonAsync<List<BeneficiaryBody>>();
        list!.Single(b => b.IsDefault).Id.ShouldBe(me);
    }

    [Fact]
    public async Task Delete_Guards()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("ben-del@example.com", "bendel");
        Guid unused = await CreateBeneficiaryAsync(client, "Trống");
        (await client.DeleteAsync($"/beneficiaries/{unused}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);

        // Foreign user's beneficiary is a 404.
        Guid mine = await CreateBeneficiaryAsync(client, "Của tôi");
        HttpClient other = await CreateAuthenticatedClientAsync("ben-other@example.com", "benother");
        (await other.DeleteAsync($"/beneficiaries/{mine}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }
```

(The `InUse` guard test lands in Task 3 once transactions can reference a beneficiary.)

- [ ] **Step 2: Verify FAIL** → 404/405.

- [ ] **Step 3: Implement** — all three handlers mirror their Plans counterparts (`UpdatePlanCommandHandler`, `SetDefaultPlanCommandHandler`, `DeletePlanCommandHandler`) with these deltas:
  - Update: after `Rename` succeeds, duplicate-name check (same predicate as create, excluding `b.Id == command.Id`) → `Beneficiaries.Duplicate`.
  - Delete: NO default-guard (spec allows deleting an unreferenced default). In THIS task delete is simply load → remove → save. `Transaction.BeneficiaryId` does not exist yet, so do NOT reference it here — the `InUse` guard and its test are added in Task 3 together with the column.
  - Endpoints: `UpdateBeneficiary` (with `UpdateBeneficiaryRequest(string Name)` record), `SetDefaultBeneficiary` (`PUT /beneficiaries/{id:guid}/default`), `DeleteBeneficiary` — mirror `PlanEndpoints.cs` classes. Register handlers.

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 5: Commit** — `git commit -am "feat: rename, delete and set-default for beneficiaries"`

---

### Task 3: BE — Transaction.BeneficiaryId + validation + projection + InUse guard

**Files:**
- Modify: `src/Domain/Transactions/Transaction.cs`, `TransactionErrors.cs`
- Modify: `src/Application/Transactions/CreateTransactionCommand.cs` + handler, `UpdateTransactionCommand.cs` + handler, `Data/TransactionResponse.cs`, `GetTransactionsByMonthQueryHandler.cs`
- Modify: `src/Application/Beneficiaries/DeleteBeneficiaryCommandHandler.cs` (add InUse guard)
- Modify: `src/Infrastructure/Transactions/TransactionConfiguration.cs`
- Create: migration `AddTransactionBeneficiaryId`
- Test: `tests/Api.IntegrationTests/Transactions/TransactionsEndpointsTests.cs`, `tests/Api.IntegrationTests/Beneficiaries/BeneficiariesEndpointsTests.cs`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: `Transaction.BeneficiaryId : Guid?`; `Create`/`Update` gain trailing optional `Guid? beneficiaryId = null`; commands gain `Guid? BeneficiaryId = null` (optional, after `SubCategoryId`); `TransactionResponse` gains `Guid? BeneficiaryId` + `string? BeneficiaryName`; error `Transactions.BeneficiaryDebitOnly`; import rows never set a beneficiary.

- [ ] **Step 1: Failing tests** (append to `TransactionsEndpointsTests`; reuse its plan/category helpers):

```csharp
    [Fact]
    public async Task Beneficiary_OnDebit_RoundTrips()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("ben-tx@example.com", "bentx");
        Guid categoryId = await CreateCategoryAsync(client, "Chi Ben", "tag");
        Guid planId = await GetDefaultPlanIdAsync(client);
        var ben = await client.PostAsJsonAsync("/beneficiaries", new { name = "Con" });
        Guid benId = (await ben.Content.ReadFromJsonAsync<CreatedBody>())!.Id;

        var create = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Học phí", creditAmount = 0m, debitAmount = 2_000_000m,
            note = (string?)null, categoryId, planId, beneficiaryId = benId
        });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);

        var summary = await (await client.GetAsync($"/transactions?month=2026-08&planId={planId}"))
            .Content.ReadFromJsonAsync<SummaryBody>();
        summary!.Items[0].BeneficiaryId.ShouldBe(benId);
        summary.Items[0].BeneficiaryName.ShouldBe("Con");

        // Credit with a beneficiary is rejected.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Lương", creditAmount = 1_000_000m, debitAmount = 0m,
            note = (string?)null, categoryId, planId, beneficiaryId = benId
        })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        // Unknown beneficiary is a 404.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Chi", creditAmount = 0m, debitAmount = 100m,
            note = (string?)null, categoryId, planId, beneficiaryId = Guid.NewGuid()
        })).StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }
```

And in `BeneficiariesEndpointsTests`, extend `Delete_Guards` (or add a fact) — create a beneficiary, attach it to a debit transaction (default plan + a category), `DELETE` → 409; update the transaction to `beneficiaryId = null` → `DELETE` → 204.
`SummaryBody`'s item record in the test file must gain `Guid? BeneficiaryId, string? BeneficiaryName` (check its current shape and extend).

- [ ] **Step 2: Verify FAIL.**

- [ ] **Step 3: Implement**
  - `Transaction.cs`: property `public Guid? BeneficiaryId { get; private set; }` after `SubCategoryId`; `Create`/`Update` gain trailing `Guid? beneficiaryId = null` param; assign; in `Validate` no change (rule enforced in handlers where amounts are known as Money):
    actually enforce in the entity where both values exist — add to `Create`/`Update` before assignment:

```csharp
        if (beneficiaryId is not null && debit.Amount <= 0m)
        {
            return Result.Failure<Transaction>(TransactionErrors.BeneficiaryDebitOnly);
        }
```

    (`Result.Failure` non-generic in `Update`; use the local `credit`/`debit` variable names the file actually has.)
  - `TransactionErrors.cs`:

```csharp
    public static readonly Error BeneficiaryDebitOnly = Error.Validation(
        "Transactions.BeneficiaryDebitOnly",
        "A beneficiary can only be set on a money-out transaction.");
```

  - Commands: `Guid? BeneficiaryId = null` appended after `SubCategoryId` (before Update's `ReimbursedByTransactionId`? — append at the END of each record's parameter list to avoid re-ordering optionals; JSON binds by name).
  - Handlers (Create + Update): ownership check when set, right after the plan check:

```csharp
        if (command.BeneficiaryId is { } beneficiaryId)
        {
            bool beneficiaryExists = await dbContext.Beneficiaries.AnyAsync(
                b => b.Id == beneficiaryId && b.UserId == userId, cancellationToken);
            if (!beneficiaryExists)
            {
                return Result.Failure<Guid>(BeneficiaryErrors.NotFound);
            }
        }
```

    Pass `command.BeneficiaryId` into `Transaction.Create(...)`/`.Update(...)`. Import handler: unchanged (rows never carry one).
  - `TransactionResponse`: append `Guid? BeneficiaryId = null, string? BeneficiaryName = null` positional params at the END; project in `GetTransactionsByMonthQueryHandler` like `subCategoryName`:

```csharp
                t.BeneficiaryId,
                dbContext.Beneficiaries
                    .Where(b => b.Id == t.BeneficiaryId)
                    .Select(b => b.Name)
                    .FirstOrDefault()
```

    (Match the projection's actual positional/named style — if the record can't take trailing defaults positionally in the Select, use the constructor with all args; compiler guides.)
  - Delete handler InUse guard (before Remove): the `AnyAsync(t => t.BeneficiaryId == beneficiary.Id)` block from Task 2's note → `BeneficiaryErrors.InUse`.
  - `TransactionConfiguration`: FK `HasOne<Domain.Beneficiaries.Beneficiary>().WithMany().HasForeignKey(t => t.BeneficiaryId).OnDelete(DeleteBehavior.Restrict);` (nullable FK — no index needed beyond default).
  - Migration `AddTransactionBeneficiaryId` — scaffolded as-is (nullable column + FK), no hand edits.

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test` (unit-test fixtures constructing `Transaction.Create` are unaffected: new param is optional/trailing).

- [ ] **Step 5: Commit** — `git commit -am "feat: optional beneficiary on debit transactions"`

---

### Task 4: BE — resx keys, push

**Files:**
- Modify: `src/Web.Api/Resources/SharedResource.vi.resx`, `SharedResource.en.resx`

Add IDENTICAL key sets to both files (vi values first list, en second). Insert error codes near existing `Plans.*` block, UI keys near `plans.*`/`menu.*` siblings.

vi:

```xml
  <data name="Beneficiaries.NameRequired" xml:space="preserve"><value>Vui lòng nhập tên đối tượng.</value></data>
  <data name="Beneficiaries.NameTooLong" xml:space="preserve"><value>Tên đối tượng tối đa 100 ký tự.</value></data>
  <data name="Beneficiaries.Duplicate" xml:space="preserve"><value>Đối tượng này đã tồn tại.</value></data>
  <data name="Beneficiaries.NotFound" xml:space="preserve"><value>Không tìm thấy đối tượng.</value></data>
  <data name="Beneficiaries.InUse" xml:space="preserve"><value>Đối tượng đang được dùng bởi giao dịch, không thể xóa.</value></data>
  <data name="Transactions.BeneficiaryDebitOnly" xml:space="preserve"><value>Đối tượng chỉ áp dụng cho giao dịch ghi nợ.</value></data>
  <data name="menu.beneficiaries" xml:space="preserve"><value>Đối tượng</value></data>
  <data name="beneficiaries.title" xml:space="preserve"><value>Quản lý đối tượng</value></data>
  <data name="beneficiaries.create" xml:space="preserve"><value>Thêm đối tượng</value></data>
  <data name="beneficiaries.name" xml:space="preserve"><value>Tên đối tượng</value></data>
  <data name="beneficiaries.rename" xml:space="preserve"><value>Đổi tên</value></data>
  <data name="beneficiaries.delete" xml:space="preserve"><value>Xóa đối tượng</value></data>
  <data name="beneficiaries.deleteConfirm" xml:space="preserve"><value>Xóa đối tượng này?</value></data>
  <data name="beneficiaries.default" xml:space="preserve"><value>Mặc định</value></data>
  <data name="beneficiaries.setDefault" xml:space="preserve"><value>Đặt mặc định</value></data>
  <data name="beneficiaries.none" xml:space="preserve"><value>Không có</value></data>
  <data name="form.beneficiary" xml:space="preserve"><value>Đối tượng</value></data>
  <data name="filters.beneficiary" xml:space="preserve"><value>Đối tượng</value></data>
  <data name="export.colBeneficiary" xml:space="preserve"><value>Đối tượng</value></data>
```

en:

```xml
  <data name="Beneficiaries.NameRequired" xml:space="preserve"><value>Please enter a name for the person.</value></data>
  <data name="Beneficiaries.NameTooLong" xml:space="preserve"><value>Name must be at most 100 characters.</value></data>
  <data name="Beneficiaries.Duplicate" xml:space="preserve"><value>This person already exists.</value></data>
  <data name="Beneficiaries.NotFound" xml:space="preserve"><value>Person not found.</value></data>
  <data name="Beneficiaries.InUse" xml:space="preserve"><value>This person is used by transactions and cannot be deleted.</value></data>
  <data name="Transactions.BeneficiaryDebitOnly" xml:space="preserve"><value>A person can only be set on a money-out transaction.</value></data>
  <data name="menu.beneficiaries" xml:space="preserve"><value>People</value></data>
  <data name="beneficiaries.title" xml:space="preserve"><value>Manage people</value></data>
  <data name="beneficiaries.create" xml:space="preserve"><value>Add person</value></data>
  <data name="beneficiaries.name" xml:space="preserve"><value>Person name</value></data>
  <data name="beneficiaries.rename" xml:space="preserve"><value>Rename</value></data>
  <data name="beneficiaries.delete" xml:space="preserve"><value>Delete person</value></data>
  <data name="beneficiaries.deleteConfirm" xml:space="preserve"><value>Delete this person?</value></data>
  <data name="beneficiaries.default" xml:space="preserve"><value>Default</value></data>
  <data name="beneficiaries.setDefault" xml:space="preserve"><value>Set default</value></data>
  <data name="beneficiaries.none" xml:space="preserve"><value>None</value></data>
  <data name="form.beneficiary" xml:space="preserve"><value>Person</value></data>
  <data name="filters.beneficiary" xml:space="preserve"><value>Person</value></data>
  <data name="export.colBeneficiary" xml:space="preserve"><value>Person</value></data>
```

- [ ] Verify `dotnet build && dotnet test`, commit `feat: beneficiary resx keys (vi/en)`, `git push -u origin feature/beneficiaries`.

---

### Task 5: FE — types, api, context

**Files:**
- Create: `src/api/beneficiaryApi.ts`, `src/beneficiaries/BeneficiariesContext.tsx`
- Modify: `src/api/types.ts`
- Test: `src/beneficiaries/BeneficiariesContext.test.tsx`

**Interfaces:**
- Produces: `BeneficiaryResponse { id, name, isDefault }`; `TransactionResponse` gains `beneficiaryId: string | null; beneficiaryName: string | null`; `TransactionPayload.beneficiaryId: string | null`; `getBeneficiaries/createBeneficiary/updateBeneficiary/deleteBeneficiary/setDefaultBeneficiary`; `BeneficiariesProvider` + `useBeneficiaries(): { beneficiaries, refresh }`.

- [ ] **Step 1: Branch** — `cd ../dmoney-tracker-web && git checkout feature/plans && git pull && git checkout -b feature/beneficiaries`
- [ ] **Step 2: Failing test** — clone the shape of `src/plans/PlanContext.test.tsx`'s simplest cases: provider loads list (mock `getBeneficiaries`), exposes `beneficiaries`, `refresh` refetches. 2 tests suffice (load + refresh).
- [ ] **Step 3: Implement** — `beneficiaryApi.ts` mirrors `planApi.ts` (+ `setDefaultBeneficiary(id) → PUT /beneficiaries/${id}/default` mirroring `setDefaultPlan`); context mirrors `CategoriesContext.tsx` verbatim (list + refresh only — no selection state; the DEFAULT lives in the data as `isDefault`). types.ts: add `BeneficiaryResponse`; extend `TransactionResponse` and `TransactionPayload` (all existing fixtures must gain the two nullable fields — the compiler enumerates them; set `beneficiaryId: null, beneficiaryName: null`).
- [ ] **Step 4: Gates + commit** — `feat: beneficiary api and context`

---

### Task 6: FE — settings page

**Files:**
- Create: `src/pages/BeneficiarySettingsPage.tsx`
- Modify: `src/App.tsx`, `src/layouts/AppLayout.tsx`
- Test: `src/pages/BeneficiarySettingsPage.test.tsx`

- [ ] **Step 1: Failing test** — clone `src/pages/PlanSettingsPage.test.tsx` structure: lists with default badge; rename calls `updateBeneficiary` + refresh; set-default button calls `setDefaultBeneficiary('b-2')`; delete confirm calls `deleteBeneficiary`. Mock `../beneficiaries/BeneficiariesContext` + `../api/beneficiaryApi` + i18n.
- [ ] **Step 2: Implement** — clone `src/pages/PlanSettingsPage.tsx` INCLUDING its Star set-default button, with beneficiary naming/labels (`beneficiaries.*` keys), create via a small inline dialog (clone `CreatePlanDialog` as `src/beneficiaries/CreateBeneficiaryDialog.tsx` with `createBeneficiary`; onCreated → `refresh()` only, no selection). Delete button always rendered (no default-guard client-side — server enforces InUse only); surface API errors via toast.
  Route: `<Route path="settings/beneficiaries" element={<BeneficiarySettingsPage />} />`. Sidebar `SETTINGS_ITEMS`: `{ to: '/app/settings/beneficiaries', key: 'menu.beneficiaries', icon: Users }` (lucide `Users`).
  Wrap: `BeneficiariesProvider` goes in `AppLayout` inside `PlanProvider`.
- [ ] **Step 3: Gates + commit** — `feat: beneficiary settings page with set-default`

---

### Task 7: FE — transaction form select (debit only, default preselect)

**Files:**
- Modify: `src/components/TransactionFormModal.tsx`, `src/pages/TransactionsPage.tsx` (payload passthrough)
- Test: `src/components/TransactionFormModal.test.tsx`

**Interfaces:**
- Produces: `TransactionFormValues.beneficiaryId: string | null`; submitted null whenever type = 'in'.

- [ ] **Step 1: Failing tests** (mock `../beneficiaries/BeneficiariesContext` in the modal test file with `[{ id: 'b-me', name: 'Tôi', isDefault: true }, { id: 'b-con', name: 'Con', isDefault: false }]`):
  1. create mode, type out (the default) → combobox `form.beneficiary` present and shows "Tôi" (default preselected); submit → `values.beneficiaryId === 'b-me'`.
  2. switch type to 'in' (click radio `form.moneyIn`) → the combobox disappears; submit a valid credit → `values.beneficiaryId === null`.
  3. pick "Con" then submit → `'b-con'`.
- [ ] **Step 2: Implement** — in the modal: `const { beneficiaries } = useBeneficiaries()`; state `const [beneficiaryId, setBeneficiaryId] = useState<string | null>(null)`; hydration effect: edit → `setBeneficiaryId(editing.beneficiaryId)`, create-reset → `setBeneficiaryId(beneficiaries.find(b => b.isDefault)?.id ?? null)` (closure-read `beneficiaries` — do NOT add it to the reset effect deps; same convention as `t`/`selectedPlanId` there). Render inside the existing `type === 'out'` block (`TransactionFormModal.tsx:391` area), a labelled Select with an explicit "—" none item (value `'none'` mapped to null — radix Select forbids empty-string item values):

```tsx
<div className="grid gap-1.5">
  <span className="text-xs text-muted-foreground">{t('form.beneficiary')}</span>
  <Select
    value={beneficiaryId ?? 'none'}
    onValueChange={(value) => setBeneficiaryId(value === 'none' ? null : value)}
  >
    <SelectTrigger aria-label={t('form.beneficiary')} className="w-full">
      <SelectValue />
    </SelectTrigger>
    <SelectContent>
      <SelectItem value="none">—</SelectItem>
      {beneficiaries.map((b) => (
        <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>
      ))}
    </SelectContent>
  </Select>
</div>
```

  Submit values: `beneficiaryId: type === 'out' ? beneficiaryId : null`. Add `beneficiaryId` to `TransactionFormValues`. `TransactionsPage.handleSubmit` payload adds `beneficiaryId: values.beneficiaryId` (after `subCategoryId`). Its page test mocks need the BeneficiariesContext mock too (empty list is fine there).
- [ ] **Step 3: Gates + commit** — `feat: beneficiary select on money-out form`

---

### Task 8: FE — filter, row chip, Excel column

**Files:**
- Modify: `src/pages/TransactionsPage.tsx`, `src/utils/exportExcel.ts`
- Test: `src/pages/TransactionsPage.test.tsx`

- [ ] **Step 1: Failing test** — extend the page test: fixtures gain `beneficiaryId`/`beneficiaryName` (`'b-me'/'Tôi'` on one debit row, null on others); render, open filters (click the expand toggle — `aria-label` `filters.expand`), select beneficiary "Tôi" in combobox `filters.beneficiary`; assert only that row remains and the summary card shows its debit total; also assert selecting `beneficiaries.none` shows only beneficiary-less rows.
- [ ] **Step 2: Implement**
  - State `const [filterBeneficiary, setFilterBeneficiary] = useState<string>('all')` (values: `'all' | 'none' | <id>`), reset in the existing filter-reset button.
  - Items filter (with the other clauses at `TransactionsPage.tsx:154-161`):

```ts
    if (filterBeneficiary === 'none' && tx.beneficiaryId !== null) return false
    if (filterBeneficiary !== 'all' && filterBeneficiary !== 'none' && tx.beneficiaryId !== filterBeneficiary) return false
```

  - Filter UI: a Select in the same grid as the category filter (label `filters.beneficiary`; items: `transactions.filterAll`, `beneficiaries.none`, then `useBeneficiaries()` list).
  - Row chip: next to the subCategory chip, when `tx.beneficiaryName`:

```tsx
{tx.beneficiaryName && (
  <span className="rounded-md bg-rose-50 px-1.5 py-0.5 text-rose-700">{tx.beneficiaryName}</span>
)}
```

  - `exportExcel.ts`: add `[t('export.colBeneficiary')]: tx.beneficiaryName ?? ''` after the debit column; widen `!cols` array by one `{ wch: 14 }` at the matching position.
- [ ] **Step 3: Gates + commit + push** — `feat: beneficiary filter, chip and export column`; `git push -u origin feature/beneficiaries`

---

### Task 9: E2E, cleanup, docs

- [ ] **Step 1:** `cd ../dmoney-tracker-orchestrator && docker compose up --build -d`; drive via API: register fresh user → create 2 beneficiaries → set default → debit with beneficiary + debit without + credit-with-beneficiary rejected (400) → summary shows beneficiaryId/Name → delete referenced beneficiary → 409; unlink → 204. Then check the web UI serves and (if feasible) the form shows the select.
- [ ] **Step 2: CLEANUP (mandatory, per memory):** delete every test user created (SQL through `docker exec dmoney-postgres psql`), verify zero `%example.com%` users and no leftover global categories created by the run.
- [ ] **Step 3:** Update orchestrator `.claude/skills/dmoney-platform/SKILL.md` contracts table (row: Beneficiary DTO + `beneficiaryId` on transaction payloads/responses) and `dmoney-web/SKILL.md` pages line (`/app/settings/beneficiaries`). Commit + push orchestrator main.
- [ ] **Step 4:** Confirm both feature branches pushed; offer PR creation (gh permission caveat from the plans cycle may still apply).
