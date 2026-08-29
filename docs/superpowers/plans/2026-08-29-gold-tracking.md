# Gold Tracking (Vàng) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transactions can carry an optional gold pair (`goldTypeId` + `goldQuantity` in chỉ) — debit = buy, credit = sell — with user-defined gold types managed in Settings and a new **Vàng** page showing per-type holdings, average cost and trade history.

**Architecture:** New `GoldType` aggregate mirroring the Beneficiaries vertical slice (no set-default), nullable `Transaction.GoldTypeId` + `GoldQuantity` with both-or-neither validation, fields projected into `TransactionResponse`, plus a user-level (cross-plan) `GET /gold/summary` aggregate endpoint; FE adds a context, a settings page cloned from BeneficiarySettingsPage, a form toggle revealing type+quantity inputs (both money directions), a `/app/gold` page, a row chip and two export columns.

**Tech Stack:** .NET 10 Clean Architecture + custom CQRS + EF Core/Npgsql, xUnit/Shouldly/Testcontainers; Vite + React 19 + TS + shadcn, vitest.

**Spec:** `docs/superpowers/specs/2026-08-29-gold-tracking-design.md` (orchestrator repo).

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`; branch `feature/gold` off `feature/beneficiaries` in BOTH (feature branches stack; `main` is still the initial import). Never commit code in the orchestrator repo.
- Handlers are registered EXPLICITLY in BE `src/Application/DependencyInjection.cs`; endpoints and EF configurations are auto-discovered by assembly scan (no registration edits for those).
- Architecture tests enforce `internal sealed` handlers named `*CommandHandler`/`*QueryHandler` and layer direction — comply or the build fails.
- `GoldTypeConstants.NameMaxLength = 100`; name required, trimmed, unique per user (`GoldTypes.Duplicate`, Conflict).
- `Transaction.GoldTypeId` (Guid?, FK `DeleteBehavior.Restrict`) and `Transaction.GoldQuantity` (decimal?, column `numeric(18,4)`), NO backfill. Both-or-neither → else `Transactions.GoldPairRequired` (400); quantity > 0 → else `Transactions.GoldQuantityInvalid` (400); unknown/foreign type → `GoldTypes.NotFound` (404). Allowed on debit (buy) AND credit (sell).
- Delete guard: gold type referenced by any transaction → `GoldTypes.InUse` (409).
- `Money` is VND-only — gold quantity is a plain `decimal`, never a `Money`.
- PUT /transactions has an explicit `UpdateTransactionRequest` DTO — new fields MUST be hand-threaded into the command there, with an update-path integration test (per the update-endpoint memory).
- Unit is chỉ; fractions allowed (e.g. 0.5). FE has NO decimal-input precedent — the gold quantity input introduces `inputMode="decimal"` + `replace(/[^\d.,]/g, '')` + `Number(text.replace(',', '.'))`. `formatMoney` pins 0 fraction digits — gold quantities use a new `formatGoldQuantity` (max 2 fraction digits).
- resx: both `SharedResource.vi.resx` + `SharedResource.en.resx`, identical key sets, key = error code; UI keys listed in Task 5 verbatim. Missing keys fall back silently to the raw key — not caught by tests.
- BE gates per task: `dotnet build && dotnet test`. FE gates: `npm test && npm run build && npm run lint` (no NEW lint warnings; `npm run build` type-checks tests).
- EF migrations: `dotnet tool restore` once, then `dotnet dotnet-ef migrations add <Name> --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations` (local tool; `--output-dir` mandatory).
- After E2E against the docker stack: DELETE all test users and any gold types/categories the run created (cleanup memory).

---

### Task 1: BE — GoldType entity, table, GET + POST

**Files:**
- Create: `src/Domain/GoldTypes/GoldType.cs`, `GoldTypeConstants.cs`, `GoldTypeErrors.cs`
- Create: `src/Infrastructure/GoldTypes/GoldTypeConfiguration.cs`
- Create: `src/Application/GoldTypes/Data/GoldTypeResponse.cs`, `GetGoldTypesQuery.cs`, `GetGoldTypesQueryHandler.cs`, `GoldTypeCommands.cs`, `CreateGoldTypeCommandHandler.cs`
- Create: `src/Web.Api/Endpoints/GoldTypes/GoldTypeEndpoints.cs`
- Create: migration `AddGoldTypes`
- Modify: `src/Application/Abstractions/Data/IApplicationDbContext.cs`, `src/Infrastructure/Database/ApplicationDbContext.cs`, `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/GoldTypes/GoldTypesEndpointsTests.cs`

**Interfaces:**
- Produces: `GoldType.Create(Guid userId, string name)`, `GoldType.Rename(string)`; `GoldTypeErrors.{NameRequired,NameTooLong,Duplicate,NotFound,InUse}`; `GoldTypeResponse(Guid Id, string Name)`; `GET /gold-types` (ordered by name), `POST /gold-types {name}` → 201 `{id}`; records `UpdateGoldTypeCommand(Guid Id, string Name)`, `DeleteGoldTypeCommand(Guid Id)` (handlers in Task 2); `dbContext.GoldTypes`.

- [ ] **Step 1: Branch setup**

```bash
cd ../dmoney-tracker-be && git checkout feature/beneficiaries && git pull && git checkout -b feature/gold
```

- [ ] **Step 2: Failing integration tests** — new file; copy `CreateAuthenticatedClientAsync` + `LoginBody`/`CreatedBody` records from `tests/Api.IntegrationTests/Beneficiaries/BeneficiariesEndpointsTests.cs` (per-file duplication is that project's convention):

```csharp
    internal sealed record GoldTypeBody(Guid Id, string Name);

    private static async Task<Guid> CreateGoldTypeAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/gold-types", new { name });
        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<CreatedBody>())!.Id;
    }

    [Fact]
    public async Task GetGoldTypes_WithoutToken_Returns401()
    {
        (await factory.CreateClient().GetAsync("/gold-types")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task CreateAndList_Works()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-create@example.com", "goldcreate");

        (await client.PostAsJsonAsync("/gold-types", new { name = "SJC miếng" })).StatusCode.ShouldBe(HttpStatusCode.Created);
        (await client.PostAsJsonAsync("/gold-types", new { name = "Nhẫn trơn 9999" })).StatusCode.ShouldBe(HttpStatusCode.Created);
        // Duplicate name (same user) is a conflict.
        (await client.PostAsJsonAsync("/gold-types", new { name = "SJC miếng" })).StatusCode.ShouldBe(HttpStatusCode.Conflict);
        // Empty name is a validation error.
        (await client.PostAsJsonAsync("/gold-types", new { name = " " })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        var list = await (await client.GetAsync("/gold-types")).Content.ReadFromJsonAsync<List<GoldTypeBody>>();
        list!.Count.ShouldBe(2);
        list.Select(g => g.Name).ShouldBe(new[] { "Nhẫn trơn 9999", "SJC miếng" }); // ordered by name
    }
```

- [ ] **Step 3: Run to verify FAIL** — `dotnet test --filter GoldTypesEndpointsTests` → 404s.

- [ ] **Step 4: Domain** — mirror `src/Domain/Beneficiaries/{Beneficiary,BeneficiaryConstants,BeneficiaryErrors}.cs` with Beneficiary→GoldType renames and NO `IsDefault`/`MakeDefault`/`ClearDefault` (gold types have no default). `GoldType` keeps `Create(Guid userId, string name)` (drop the `isDefault` param) and `Rename`. `GoldTypeErrors`:

```csharp
using SharedKernel;

namespace Domain.GoldTypes;

public static class GoldTypeErrors
{
    public static readonly Error NameRequired = Error.Validation(
        "GoldTypes.NameRequired", "Please enter a name for the gold type.");

    public static readonly Error NameTooLong = Error.Validation(
        "GoldTypes.NameTooLong",
        $"Name must be at most {GoldTypeConstants.NameMaxLength} characters.");

    public static readonly Error Duplicate = Error.Conflict(
        "GoldTypes.Duplicate", "This gold type already exists.");

    public static readonly Error NotFound = Error.NotFound(
        "GoldTypes.NotFound", "Gold type not found.");

    public static readonly Error InUse = Error.Conflict(
        "GoldTypes.InUse", "This gold type is used by transactions and cannot be deleted.");
}
```

- [ ] **Step 5: EF + DbContext** — `GoldTypeConfiguration` mirrors `src/Infrastructure/Beneficiaries/BeneficiaryConfiguration.cs` exactly (table `gold_types`, Name max length + required, FK to `User` Cascade, `HasIndex(UserId)`, `Ignore(DomainEvents)`). Add `DbSet<GoldType> GoldTypes` to both `IApplicationDbContext` and `ApplicationDbContext` (property style: `public DbSet<GoldType> GoldTypes => Set<GoldType>();`).

- [ ] **Step 6: Application + endpoint** — mirror the Beneficiaries files:
  - `Data/GoldTypeResponse.cs`: `public sealed record GoldTypeResponse(Guid Id, string Name);`
  - `GetGoldTypesQuery.cs`: `public sealed record GetGoldTypesQuery : IQuery<List<GoldTypeResponse>>;`
  - `GetGoldTypesQueryHandler` = copy `GetBeneficiariesQueryHandler`, ordering just `.OrderBy(g => g.Name)`.
  - `GoldTypeCommands.cs`:

```csharp
using Application.Abstractions.Messaging;

namespace Application.GoldTypes;

public sealed record CreateGoldTypeCommand(string Name) : ICommand<Guid>;

public sealed record UpdateGoldTypeCommand(Guid Id, string Name) : ICommand;

public sealed record DeleteGoldTypeCommand(Guid Id) : ICommand;
```

  - `CreateGoldTypeCommandHandler` = copy `CreateBeneficiaryCommandHandler` (auth check → `GoldType.Create` → duplicate `AnyAsync(g => g.UserId == userId && g.Name == goldType.Value.Name)` → Add + Save).
  - `GoldTypeEndpoints.cs`: `GetGoldTypes` + `CreateGoldType` classes mirroring `BeneficiaryEndpoints.cs` (`/gold-types` routes, `RequireAuthorization`, 201 + Location `/gold-types/{id}`). Endpoint registration is automatic (assembly scan).
  - `DependencyInjection.cs`: add usings `Application.GoldTypes;` / `Application.GoldTypes.Data;` and register next to the Beneficiaries lines:

```csharp
        services.AddScoped<IQueryHandler<GetGoldTypesQuery, List<GoldTypeResponse>>, GetGoldTypesQueryHandler>();
        services.AddScoped<ICommandHandler<CreateGoldTypeCommand, Guid>, CreateGoldTypeCommandHandler>();
```

- [ ] **Step 7: Migration** — `dotnet dotnet-ef migrations add AddGoldTypes --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations`. Pure new table, no hand edits.

- [ ] **Step 8: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 9: Commit** — `git add -A && git commit -m "feat: gold type entity with list and create endpoints"`

---

### Task 2: BE — rename + guarded delete for gold types

**Files:**
- Create: `src/Application/GoldTypes/UpdateGoldTypeCommandHandler.cs`, `DeleteGoldTypeCommandHandler.cs`
- Modify: `src/Web.Api/Endpoints/GoldTypes/GoldTypeEndpoints.cs`, `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/GoldTypes/GoldTypesEndpointsTests.cs`

**Interfaces:**
- Consumes: Task 1 records + entity methods.
- Produces: `PUT /gold-types/{id} {name}` → 204; `DELETE /gold-types/{id}` → 204 | 404. (The 409 `InUse` guard and its test land in Task 3, once `Transaction.GoldTypeId` exists.)

- [ ] **Step 1: Failing tests** (append):

```csharp
    [Fact]
    public async Task Rename_Works_AndChecksDuplicates()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-rename@example.com", "goldrename");
        Guid ring = await CreateGoldTypeAsync(client, "Nhẫn trơn");
        await CreateGoldTypeAsync(client, "SJC");

        (await client.PutAsJsonAsync($"/gold-types/{ring}", new { name = "Nhẫn trơn 9999" }))
            .StatusCode.ShouldBe(HttpStatusCode.NoContent);
        // Renaming onto an existing name is a conflict.
        (await client.PutAsJsonAsync($"/gold-types/{ring}", new { name = "SJC" }))
            .StatusCode.ShouldBe(HttpStatusCode.Conflict);

        var list = await (await client.GetAsync("/gold-types")).Content.ReadFromJsonAsync<List<GoldTypeBody>>();
        list!.Select(g => g.Name).ShouldContain("Nhẫn trơn 9999");
    }

    [Fact]
    public async Task Delete_Guards()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-del@example.com", "golddel");
        Guid unused = await CreateGoldTypeAsync(client, "Trống");
        (await client.DeleteAsync($"/gold-types/{unused}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);

        // Foreign user's gold type is a 404.
        Guid mine = await CreateGoldTypeAsync(client, "Của tôi");
        HttpClient other = await CreateAuthenticatedClientAsync("gold-other@example.com", "goldother");
        (await other.DeleteAsync($"/gold-types/{mine}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }
```

- [ ] **Step 2: Verify FAIL** → 404/405.

- [ ] **Step 3: Implement** — both handlers mirror `UpdateBeneficiaryCommandHandler` / `DeleteBeneficiaryCommandHandler`:
  - Update: load by `Id + UserId` → 404 `GoldTypes.NotFound`; `Rename`; duplicate re-check `AnyAsync(g => g.UserId == userId && g.Name == goldType.Name && g.Id != command.Id)` → `GoldTypes.Duplicate`; Save.
  - Delete: load → Remove → Save. `Transaction.GoldTypeId` does not exist yet, so do NOT reference it here — the `InUse` guard and its test are added in Task 3 together with the column.
  - Endpoints: `UpdateGoldType` (with `internal sealed record UpdateGoldTypeRequest(string Name);`) and `DeleteGoldType`, mirroring the `UpdateBeneficiary`/`DeleteBeneficiary` classes (`/gold-types/{id:guid}` routes).
  - Register both handlers in `DependencyInjection.cs`.

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 5: Commit** — `git commit -am "feat: rename and delete for gold types"`

---

### Task 3: BE — Transaction gold fields + validation + projection + InUse guard

**Files:**
- Modify: `src/Domain/Transactions/Transaction.cs`, `TransactionErrors.cs`
- Modify: `src/Application/Transactions/CreateTransactionCommand.cs` + handler, `UpdateTransactionCommand.cs` + handler, `Data/TransactionResponse.cs`, `GetTransactionsByMonthQueryHandler.cs`
- Modify: `src/Web.Api/Endpoints/Transactions/UpdateTransaction.cs` (explicit request DTO — hand-thread the new fields)
- Modify: `src/Application/GoldTypes/DeleteGoldTypeCommandHandler.cs` (add InUse guard)
- Modify: `src/Infrastructure/Transactions/TransactionConfiguration.cs`
- Create: migration `AddTransactionGoldFields`
- Test: `tests/Api.IntegrationTests/Transactions/TransactionsEndpointsTests.cs`, `tests/Api.IntegrationTests/GoldTypes/GoldTypesEndpointsTests.cs`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: `Transaction.GoldTypeId : Guid?`, `Transaction.GoldQuantity : decimal?`; `Create`/`Update` gain trailing `Guid? goldTypeId = null, decimal? goldQuantity = null`; both commands AND `UpdateTransactionRequest` gain `Guid? GoldTypeId = null, decimal? GoldQuantity = null` appended at the END; `TransactionResponse` gains `Guid? GoldTypeId = null, string? GoldTypeName = null, decimal? GoldQuantity = null`; errors `Transactions.GoldPairRequired`, `Transactions.GoldQuantityInvalid`; import rows never set gold fields.

- [ ] **Step 1: Failing tests** — in `TransactionsEndpointsTests` (reuse its `CreateCategoryAsync`/`GetDefaultPlanIdAsync` helpers; add a `CreateGoldTypeAsync` helper like Task 1's; extend `ItemBody` — deserialization is by name, appending is safe):

```csharp
    internal sealed record ItemBody(..., Guid? BeneficiaryId, string? BeneficiaryName,
        Guid? GoldTypeId, string? GoldTypeName, decimal? GoldQuantity);
```

```csharp
    [Fact]
    public async Task Gold_RoundTrips_BuyAndSell()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-tx@example.com", "goldtx");
        Guid categoryId = await CreateCategoryAsync(client, "Chi Vàng", "tag");
        Guid planId = await GetDefaultPlanIdAsync(client);
        Guid goldTypeId = await CreateGoldTypeAsync(client, "Nhẫn trơn");

        // Buy: money-out + quantity.
        var buy = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Mua 2 chỉ", creditAmount = 0m, debitAmount = 20_000_000m,
            note = (string?)null, categoryId, planId, goldTypeId, goldQuantity = 2m
        });
        buy.StatusCode.ShouldBe(HttpStatusCode.Created);

        // Sell: money-in + quantity.
        var sell = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-11", content = "Bán 0.5 chỉ", creditAmount = 6_000_000m, debitAmount = 0m,
            note = (string?)null, categoryId, planId, goldTypeId, goldQuantity = 0.5m
        });
        sell.StatusCode.ShouldBe(HttpStatusCode.Created);

        var summary = await (await client.GetAsync($"/transactions?month=2026-08&planId={planId}"))
            .Content.ReadFromJsonAsync<SummaryBody>();
        ItemBody bought = summary!.Items.Single(i => i.Content == "Mua 2 chỉ");
        bought.GoldTypeId.ShouldBe(goldTypeId);
        bought.GoldTypeName.ShouldBe("Nhẫn trơn");
        bought.GoldQuantity.ShouldBe(2m);
        summary.Items.Single(i => i.Content == "Bán 0.5 chỉ").GoldQuantity.ShouldBe(0.5m);
    }

    [Fact]
    public async Task Gold_Validation()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-val@example.com", "goldval");
        Guid categoryId = await CreateCategoryAsync(client, "Chi GVal", "tag");
        Guid planId = await GetDefaultPlanIdAsync(client);
        Guid goldTypeId = await CreateGoldTypeAsync(client, "SJC");

        // Type without quantity → 400.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Thiếu chỉ", creditAmount = 0m, debitAmount = 100m,
            note = (string?)null, categoryId, planId, goldTypeId
        })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        // Quantity without type → 400.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Thiếu loại", creditAmount = 0m, debitAmount = 100m,
            note = (string?)null, categoryId, planId, goldQuantity = 1m
        })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        // Quantity <= 0 → 400.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Số âm", creditAmount = 0m, debitAmount = 100m,
            note = (string?)null, categoryId, planId, goldTypeId, goldQuantity = 0m
        })).StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        // Unknown gold type → 404.
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Lạ", creditAmount = 0m, debitAmount = 100m,
            note = (string?)null, categoryId, planId, goldTypeId = Guid.NewGuid(), goldQuantity = 1m
        })).StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Gold_UpdatePath_ThreadsFields()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-upd@example.com", "goldupd");
        Guid categoryId = await CreateCategoryAsync(client, "Chi GUpd", "tag");
        Guid planId = await GetDefaultPlanIdAsync(client);
        Guid goldTypeId = await CreateGoldTypeAsync(client, "PNJ");

        var create = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Chưa vàng", creditAmount = 0m, debitAmount = 5_000_000m,
            note = (string?)null, categoryId, planId
        });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);
        Guid transactionId = (await create.Content.ReadFromJsonAsync<CreatedBody>())!.Id;

        // PUT with the gold pair — guards the explicit request-DTO threading.
        (await client.PutAsJsonAsync($"/transactions/{transactionId}", new
        {
            date = "2026-08-10", content = "Giờ là vàng", creditAmount = 0m, debitAmount = 5_000_000m,
            note = (string?)null, categoryId, planId, goldTypeId, goldQuantity = 0.5m
        })).StatusCode.ShouldBe(HttpStatusCode.NoContent);

        var summary = await (await client.GetAsync($"/transactions?month=2026-08&planId={planId}"))
            .Content.ReadFromJsonAsync<SummaryBody>();
        ItemBody item = summary!.Items.Single(i => i.Content == "Giờ là vàng");
        item.GoldTypeId.ShouldBe(goldTypeId);
        item.GoldQuantity.ShouldBe(0.5m);
    }
```

And in `GoldTypesEndpointsTests`, append (mirrors `Delete_InUse_ThenUnlink_Allows` in the beneficiaries tests — needs `CreateCategoryAsync` + `GetDefaultPlanIdAsync` + `PlanListBody` helpers copied in):

```csharp
    [Fact]
    public async Task Delete_InUse_ThenUnlink_Allows()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-inuse@example.com", "goldinuse");
        Guid goldTypeId = await CreateGoldTypeAsync(client, "Đang dùng");
        Guid planId = await GetDefaultPlanIdAsync(client);
        Guid categoryId = await CreateCategoryAsync(client, "Chi GInUse", "tag");

        var create = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-08-10", content = "Mua vàng", creditAmount = 0m, debitAmount = 10_000_000m,
            note = (string?)null, categoryId, planId, goldTypeId, goldQuantity = 1m
        });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);
        Guid transactionId = (await create.Content.ReadFromJsonAsync<CreatedBody>())!.Id;

        (await client.DeleteAsync($"/gold-types/{goldTypeId}")).StatusCode.ShouldBe(HttpStatusCode.Conflict);

        var update = await client.PutAsJsonAsync($"/transactions/{transactionId}", new
        {
            date = "2026-08-10", content = "Mua vàng", creditAmount = 0m, debitAmount = 10_000_000m,
            note = (string?)null, categoryId, planId
        });
        update.StatusCode.ShouldBe(HttpStatusCode.NoContent);

        (await client.DeleteAsync($"/gold-types/{goldTypeId}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);
    }
```

- [ ] **Step 2: Verify FAIL.**

- [ ] **Step 3: Implement**
  - `Transaction.cs`: properties after `BeneficiaryId`:

```csharp
    /// <summary>Gold type when this transaction buys (debit) or sells (credit) gold. Paired with GoldQuantity.</summary>
    public Guid? GoldTypeId { get; private set; }

    /// <summary>Gold quantity in chỉ (1 lượng = 10 chỉ). Paired with GoldTypeId.</summary>
    public decimal? GoldQuantity { get; private set; }
```

    `Create`/`Update` gain trailing `Guid? goldTypeId = null, decimal? goldQuantity = null` params (after `beneficiaryId`); guard right after the beneficiary guard, then assign both in the construction/assignment blocks:

```csharp
        if ((goldTypeId is null) != (goldQuantity is null))
        {
            return Result.Failure<Transaction>(TransactionErrors.GoldPairRequired);
        }

        if (goldQuantity is { } quantity && quantity <= 0m)
        {
            return Result.Failure<Transaction>(TransactionErrors.GoldQuantityInvalid);
        }
```

    (`Update` version drops the `<Transaction>` generic arg.)
  - `TransactionErrors.cs`:

```csharp
    public static readonly Error GoldPairRequired = Error.Validation(
        "Transactions.GoldPairRequired",
        "Gold type and gold quantity must be provided together.");

    public static readonly Error GoldQuantityInvalid = Error.Validation(
        "Transactions.GoldQuantityInvalid",
        "Gold quantity must be greater than zero.");
```

  - Commands: `Guid? GoldTypeId = null, decimal? GoldQuantity = null` appended at the END of `CreateTransactionCommand` and `UpdateTransactionCommand` (JSON binds by name).
  - `UpdateTransaction.cs` endpoint: append the same two params to `UpdateTransactionRequest` AND pass `request.GoldTypeId, request.GoldQuantity` at the end of the `new UpdateTransactionCommand(...)` call — this is the hand-threading the memory warns about.
  - Handlers (Create + Update): ownership check right after the beneficiary check block:

```csharp
        if (command.GoldTypeId is { } commandGoldTypeId)
        {
            bool goldTypeExists = await dbContext.GoldTypes.AnyAsync(
                g => g.Id == commandGoldTypeId && g.UserId == userId, cancellationToken);
            if (!goldTypeExists)
            {
                return Result.Failure<Guid>(GoldTypeErrors.NotFound);
            }
        }
```

    (non-generic `Result.Failure` in the update handler). Pass `command.GoldTypeId, command.GoldQuantity` as the new trailing args of `Transaction.Create(...)`/`.Update(...)`. Import handler: unchanged (rows never carry gold).
  - `TransactionResponse`: append `Guid? GoldTypeId = null, string? GoldTypeName = null, decimal? GoldQuantity = null`. The projection in `GetTransactionsByMonthQueryHandler` is fully positional — append three expressions after the `BeneficiaryName` subquery:

```csharp
                t.GoldTypeId,
                dbContext.GoldTypes
                    .Where(g => g.Id == t.GoldTypeId)
                    .Select(g => g.Name)
                    .FirstOrDefault(),
                t.GoldQuantity))
```

  - `DeleteGoldTypeCommandHandler` InUse guard (before Remove):

```csharp
        bool inUse = await dbContext.Transactions.AnyAsync(
            t => t.GoldTypeId == goldType.Id, cancellationToken);
        if (inUse)
        {
            return Result.Failure(GoldTypeErrors.InUse);
        }
```

  - `TransactionConfiguration` (after the beneficiary FK block):

```csharp
        builder.Property(t => t.GoldQuantity)
            .HasColumnType("numeric(18,4)");

        builder.HasOne<Domain.GoldTypes.GoldType>()
            .WithMany()
            .HasForeignKey(t => t.GoldTypeId)
            .OnDelete(DeleteBehavior.Restrict);
```

  - Migration: `dotnet dotnet-ef migrations add AddTransactionGoldFields --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations` — scaffolded as-is (nullable column + FK + index), no hand edits.

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test` (existing `Transaction.Create` fixtures unaffected: new params are trailing optionals).

- [ ] **Step 5: Commit** — `git commit -am "feat: optional gold type and quantity on transactions"`

---

### Task 4: BE — GET /gold/summary

**Files:**
- Create: `src/Application/Gold/Data/GoldSummaryResponse.cs`, `GetGoldSummaryQuery.cs`, `GetGoldSummaryQueryHandler.cs`
- Create: `src/Web.Api/Endpoints/Gold/GetGoldSummary.cs`
- Modify: `src/Application/DependencyInjection.cs`
- Test: `tests/Api.IntegrationTests/Gold/GoldSummaryEndpointTests.cs`

**Interfaces:**
- Consumes: Tasks 1-3 (`dbContext.GoldTypes`, `Transaction.GoldTypeId/GoldQuantity`).
- Produces: `GET /gold/summary` (no query params — user-level, across ALL plans) → `GoldSummaryResponse(Types, Transactions)`; `MoneyResponse` reused from `Application.Transactions.Data`.

- [ ] **Step 1: Failing tests** — new file; copy `CreateAuthenticatedClientAsync`, `LoginBody`, `CreatedBody`, `PlanListBody`, `CreateCategoryAsync`, `GetDefaultPlanIdAsync`, `CreatePlanAsync` helpers from `TransactionsEndpointsTests`, plus `CreateGoldTypeAsync` and `MoneyBody`:

```csharp
    internal sealed record GoldSummaryBody(List<GoldSummaryBody.TypeItem> Types, List<GoldSummaryBody.TxItem> Transactions)
    {
        internal sealed record TypeItem(
            Guid GoldTypeId, string Name, decimal HeldQuantity, decimal BoughtQuantity, decimal SoldQuantity,
            MoneyBody TotalSpent, MoneyBody TotalReceived, MoneyBody AverageCostPerChi);

        internal sealed record TxItem(
            Guid TransactionId, string Date, string Content, Guid GoldTypeId, string GoldTypeName,
            decimal GoldQuantity, MoneyBody Credit, MoneyBody Debit, MoneyBody PricePerChi);
    }

    [Fact]
    public async Task GoldSummary_WithoutToken_Returns401()
    {
        (await factory.CreateClient().GetAsync("/gold/summary")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GoldSummary_AggregatesAcrossPlans()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("gold-sum@example.com", "goldsum");
        Guid categoryId = await CreateCategoryAsync(client, "Chi GSum", "tag");
        Guid defaultPlanId = await GetDefaultPlanIdAsync(client);
        Guid otherPlanId = await CreatePlanAsync(client, "Sổ vàng riêng");
        Guid ring = await CreateGoldTypeAsync(client, "Nhẫn trơn");
        await CreateGoldTypeAsync(client, "SJC"); // never traded — must still appear with zeros

        async Task PostTx(Guid planId, string date, string content, decimal credit, decimal debit, decimal qty) =>
            (await client.PostAsJsonAsync("/transactions", new
            {
                date, content, creditAmount = credit, debitAmount = debit,
                note = (string?)null, categoryId, planId, goldTypeId = ring, goldQuantity = qty
            })).StatusCode.ShouldBe(HttpStatusCode.Created);

        await PostTx(defaultPlanId, "2026-08-01", "Mua 2 chỉ", 0m, 20_000_000m, 2m);
        await PostTx(otherPlanId, "2026-08-02", "Mua 1 chỉ", 0m, 11_000_000m, 1m);   // other plan — must count
        await PostTx(defaultPlanId, "2026-08-03", "Bán 1 chỉ", 12_000_000m, 0m, 1m);

        var body = await (await client.GetAsync("/gold/summary")).Content.ReadFromJsonAsync<GoldSummaryBody>();

        body!.Types.Count.ShouldBe(2); // name order: "Nhẫn trơn", "SJC"
        GoldSummaryBody.TypeItem nhan = body.Types.Single(x => x.Name == "Nhẫn trơn");
        nhan.BoughtQuantity.ShouldBe(3m);
        nhan.SoldQuantity.ShouldBe(1m);
        nhan.HeldQuantity.ShouldBe(2m);
        nhan.TotalSpent.Amount.ShouldBe(31_000_000m);
        nhan.TotalReceived.Amount.ShouldBe(12_000_000m);
        nhan.AverageCostPerChi.Amount.ShouldBe(Math.Round(31_000_000m / 3m, 2));

        GoldSummaryBody.TypeItem sjc = body.Types.Single(x => x.Name == "SJC");
        sjc.HeldQuantity.ShouldBe(0m);
        sjc.AverageCostPerChi.Amount.ShouldBe(0m);

        body.Transactions.Count.ShouldBe(3); // date desc
        body.Transactions[0].Content.ShouldBe("Bán 1 chỉ");
        body.Transactions[0].PricePerChi.Amount.ShouldBe(12_000_000m);
        body.Transactions.Single(x => x.Content == "Mua 2 chỉ").PricePerChi.Amount.ShouldBe(10_000_000m);
    }
```

- [ ] **Step 2: Verify FAIL** → 404.

- [ ] **Step 3: Implement**
  - `Data/GoldSummaryResponse.cs`:

```csharp
using Application.Transactions.Data;

namespace Application.Gold.Data;

public sealed record GoldSummaryResponse(
    IReadOnlyList<GoldTypeSummaryResponse> Types,
    IReadOnlyList<GoldTransactionResponse> Transactions);

public sealed record GoldTypeSummaryResponse(
    Guid GoldTypeId,
    string Name,
    decimal HeldQuantity,
    decimal BoughtQuantity,
    decimal SoldQuantity,
    MoneyResponse TotalSpent,
    MoneyResponse TotalReceived,
    MoneyResponse AverageCostPerChi);

public sealed record GoldTransactionResponse(
    Guid TransactionId,
    DateOnly Date,
    string Content,
    Guid GoldTypeId,
    string GoldTypeName,
    decimal GoldQuantity,
    MoneyResponse Credit,
    MoneyResponse Debit,
    MoneyResponse PricePerChi);
```

  - `GetGoldSummaryQuery.cs`: `public sealed record GetGoldSummaryQuery : IQuery<GoldSummaryResponse>;`
  - `GetGoldSummaryQueryHandler.cs` (`internal sealed`, injects `IApplicationDbContext` + `IUserContext`, auth-check like `GetBeneficiariesQueryHandler`; NO plan filter — user-level by design):

```csharp
        var rows = await dbContext.Transactions
            .Where(t => t.UserId == userId && t.GoldTypeId != null)
            .GroupBy(t => t.GoldTypeId)
            .Select(g => new
            {
                GoldTypeId = g.Key!.Value,
                BoughtQuantity = g.Sum(t => t.Debit.Amount > 0m ? t.GoldQuantity ?? 0m : 0m),
                SoldQuantity = g.Sum(t => t.Credit.Amount > 0m ? t.GoldQuantity ?? 0m : 0m),
                TotalSpent = g.Sum(t => t.Debit.Amount),
                TotalReceived = g.Sum(t => t.Credit.Amount)
            })
            .ToListAsync(cancellationToken);

        var typeRows = await dbContext.GoldTypes
            .Where(g => g.UserId == userId)
            .OrderBy(g => g.Name)
            .Select(g => new { g.Id, g.Name })
            .ToListAsync(cancellationToken);

        List<GoldTypeSummaryResponse> types = typeRows
            .Select(type =>
            {
                var row = rows.FirstOrDefault(r => r.GoldTypeId == type.Id);
                decimal bought = row?.BoughtQuantity ?? 0m;
                decimal sold = row?.SoldQuantity ?? 0m;
                decimal spent = row?.TotalSpent ?? 0m;
                decimal received = row?.TotalReceived ?? 0m;
                return new GoldTypeSummaryResponse(
                    type.Id,
                    type.Name,
                    bought - sold,
                    bought,
                    sold,
                    new MoneyResponse(spent, Money.DefaultCurrency),
                    new MoneyResponse(received, Money.DefaultCurrency),
                    new MoneyResponse(bought > 0m ? Math.Round(spent / bought, 2) : 0m, Money.DefaultCurrency));
            })
            .ToList();
```

    (Types are fetched ordered by name and left-joined to the aggregate rows in memory, so zero-trade types appear with zeros.) Then the history:

```csharp
        var txRows = await dbContext.Transactions
            .Where(t => t.UserId == userId && t.GoldTypeId != null)
            .OrderByDescending(t => t.Date)
            .ThenByDescending(t => t.CreatedAt)
            .Select(t => new
            {
                t.Id,
                t.Date,
                t.Content,
                GoldTypeId = t.GoldTypeId!.Value,
                GoldTypeName = dbContext.GoldTypes
                    .Where(g => g.Id == t.GoldTypeId)
                    .Select(g => g.Name)
                    .First(),
                GoldQuantity = t.GoldQuantity ?? 0m,
                CreditAmount = t.Credit.Amount,
                DebitAmount = t.Debit.Amount
            })
            .ToListAsync(cancellationToken);

        List<GoldTransactionResponse> transactions = txRows
            .Select(r => new GoldTransactionResponse(
                r.Id, r.Date, r.Content, r.GoldTypeId, r.GoldTypeName, r.GoldQuantity,
                new MoneyResponse(r.CreditAmount, Money.DefaultCurrency),
                new MoneyResponse(r.DebitAmount, Money.DefaultCurrency),
                new MoneyResponse(
                    r.GoldQuantity > 0m ? Math.Round((r.CreditAmount + r.DebitAmount) / r.GoldQuantity, 0) : 0m,
                    Money.DefaultCurrency)))
            .ToList();

        return new GoldSummaryResponse(types, transactions);
```

  - `GetGoldSummary.cs` endpoint — mirror `GetDashboardStats` minus the params:

```csharp
using Application.Abstractions.Messaging;
using Application.Gold;
using Application.Gold.Data;
using Microsoft.Extensions.Localization;
using SharedKernel;
using Web.Api.Infrastructure;
using Web.Api.Middleware;

namespace Web.Api.Endpoints.Gold;

internal sealed class GetGoldSummary : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapGet("/gold/summary", async (
            IQueryHandler<GetGoldSummaryQuery, GoldSummaryResponse> handler,
            IStringLocalizer<SharedResource> localizer,
            CancellationToken cancellationToken) =>
        {
            Result<GoldSummaryResponse> result = await handler.Handle(
                new GetGoldSummaryQuery(), cancellationToken);

            return result.ToHttpResult(localizer, Results.Ok);
        }).RequireAuthorization();
    }
}
```

  - Register in `DependencyInjection.cs` (usings `Application.Gold;` / `Application.Gold.Data;`):

```csharp
        services.AddScoped<IQueryHandler<GetGoldSummaryQuery, GoldSummaryResponse>, GetGoldSummaryQueryHandler>();
```

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 5: Commit** — `git commit -am "feat: gold summary endpoint with per-type holdings and history"`

---

### Task 5: BE — resx keys, push

**Files:**
- Modify: `src/Web.Api/Resources/SharedResource.vi.resx`, `SharedResource.en.resx`

Add IDENTICAL key sets to both files, in the same order (error codes near the `Beneficiaries.*` block, UI keys near `menu.*`/`form.*` siblings).

vi:

```xml
  <data name="GoldTypes.NameRequired" xml:space="preserve"><value>Vui lòng nhập tên loại vàng.</value></data>
  <data name="GoldTypes.NameTooLong" xml:space="preserve"><value>Tên loại vàng tối đa 100 ký tự.</value></data>
  <data name="GoldTypes.Duplicate" xml:space="preserve"><value>Loại vàng này đã tồn tại.</value></data>
  <data name="GoldTypes.NotFound" xml:space="preserve"><value>Không tìm thấy loại vàng.</value></data>
  <data name="GoldTypes.InUse" xml:space="preserve"><value>Loại vàng đang được dùng bởi giao dịch, không thể xóa.</value></data>
  <data name="Transactions.GoldPairRequired" xml:space="preserve"><value>Loại vàng và số chỉ phải được nhập cùng nhau.</value></data>
  <data name="Transactions.GoldQuantityInvalid" xml:space="preserve"><value>Số chỉ phải lớn hơn 0.</value></data>
  <data name="menu.gold" xml:space="preserve"><value>Vàng</value></data>
  <data name="menu.goldTypes" xml:space="preserve"><value>Loại vàng</value></data>
  <data name="gold.title" xml:space="preserve"><value>Quản lý vàng</value></data>
  <data name="gold.held" xml:space="preserve"><value>Đang giữ</value></data>
  <data name="gold.bought" xml:space="preserve"><value>Đã mua</value></data>
  <data name="gold.sold" xml:space="preserve"><value>Đã bán</value></data>
  <data name="gold.avgCost" xml:space="preserve"><value>Giá vốn TB/chỉ</value></data>
  <data name="gold.totalSpent" xml:space="preserve"><value>Tổng tiền mua</value></data>
  <data name="gold.totalReceived" xml:space="preserve"><value>Tổng tiền bán</value></data>
  <data name="gold.history" xml:space="preserve"><value>Lịch sử mua bán</value></data>
  <data name="gold.unit" xml:space="preserve"><value>chỉ</value></data>
  <data name="gold.buy" xml:space="preserve"><value>Mua</value></data>
  <data name="gold.sell" xml:space="preserve"><value>Bán</value></data>
  <data name="gold.pricePerChi" xml:space="preserve"><value>Giá/chỉ</value></data>
  <data name="gold.empty" xml:space="preserve"><value>Chưa có giao dịch vàng nào.</value></data>
  <data name="goldTypes.title" xml:space="preserve"><value>Quản lý loại vàng</value></data>
  <data name="goldTypes.create" xml:space="preserve"><value>Thêm loại vàng</value></data>
  <data name="goldTypes.name" xml:space="preserve"><value>Tên loại vàng</value></data>
  <data name="goldTypes.rename" xml:space="preserve"><value>Đổi tên</value></data>
  <data name="goldTypes.delete" xml:space="preserve"><value>Xóa loại vàng</value></data>
  <data name="goldTypes.deleteConfirm" xml:space="preserve"><value>Xóa loại vàng này?</value></data>
  <data name="form.goldToggle" xml:space="preserve"><value>Giao dịch vàng</value></data>
  <data name="form.goldToggleHint" xml:space="preserve"><value>Ghi số chỉ vàng mua (tiền ra) hoặc bán (tiền vào).</value></data>
  <data name="form.goldType" xml:space="preserve"><value>Loại vàng</value></data>
  <data name="form.goldQuantity" xml:space="preserve"><value>Số chỉ</value></data>
  <data name="form.goldTypeRequired" xml:space="preserve"><value>Vui lòng chọn loại vàng.</value></data>
  <data name="form.goldQuantityRequired" xml:space="preserve"><value>Vui lòng nhập số chỉ hợp lệ.</value></data>
  <data name="export.colGoldType" xml:space="preserve"><value>Loại vàng</value></data>
  <data name="export.colGoldQuantity" xml:space="preserve"><value>Số chỉ</value></data>
```

en:

```xml
  <data name="GoldTypes.NameRequired" xml:space="preserve"><value>Please enter a name for the gold type.</value></data>
  <data name="GoldTypes.NameTooLong" xml:space="preserve"><value>Name must be at most 100 characters.</value></data>
  <data name="GoldTypes.Duplicate" xml:space="preserve"><value>This gold type already exists.</value></data>
  <data name="GoldTypes.NotFound" xml:space="preserve"><value>Gold type not found.</value></data>
  <data name="GoldTypes.InUse" xml:space="preserve"><value>This gold type is used by transactions and cannot be deleted.</value></data>
  <data name="Transactions.GoldPairRequired" xml:space="preserve"><value>Gold type and gold quantity must be provided together.</value></data>
  <data name="Transactions.GoldQuantityInvalid" xml:space="preserve"><value>Gold quantity must be greater than zero.</value></data>
  <data name="menu.gold" xml:space="preserve"><value>Gold</value></data>
  <data name="menu.goldTypes" xml:space="preserve"><value>Gold types</value></data>
  <data name="gold.title" xml:space="preserve"><value>Gold</value></data>
  <data name="gold.held" xml:space="preserve"><value>Holding</value></data>
  <data name="gold.bought" xml:space="preserve"><value>Bought</value></data>
  <data name="gold.sold" xml:space="preserve"><value>Sold</value></data>
  <data name="gold.avgCost" xml:space="preserve"><value>Avg cost per chỉ</value></data>
  <data name="gold.totalSpent" xml:space="preserve"><value>Total spent</value></data>
  <data name="gold.totalReceived" xml:space="preserve"><value>Total received</value></data>
  <data name="gold.history" xml:space="preserve"><value>Trade history</value></data>
  <data name="gold.unit" xml:space="preserve"><value>chỉ</value></data>
  <data name="gold.buy" xml:space="preserve"><value>Buy</value></data>
  <data name="gold.sell" xml:space="preserve"><value>Sell</value></data>
  <data name="gold.pricePerChi" xml:space="preserve"><value>Price per chỉ</value></data>
  <data name="gold.empty" xml:space="preserve"><value>No gold transactions yet.</value></data>
  <data name="goldTypes.title" xml:space="preserve"><value>Manage gold types</value></data>
  <data name="goldTypes.create" xml:space="preserve"><value>Add gold type</value></data>
  <data name="goldTypes.name" xml:space="preserve"><value>Gold type name</value></data>
  <data name="goldTypes.rename" xml:space="preserve"><value>Rename</value></data>
  <data name="goldTypes.delete" xml:space="preserve"><value>Delete gold type</value></data>
  <data name="goldTypes.deleteConfirm" xml:space="preserve"><value>Delete this gold type?</value></data>
  <data name="form.goldToggle" xml:space="preserve"><value>Gold transaction</value></data>
  <data name="form.goldToggleHint" xml:space="preserve"><value>Record chỉ bought (money out) or sold (money in).</value></data>
  <data name="form.goldType" xml:space="preserve"><value>Gold type</value></data>
  <data name="form.goldQuantity" xml:space="preserve"><value>Quantity (chỉ)</value></data>
  <data name="form.goldTypeRequired" xml:space="preserve"><value>Please choose a gold type.</value></data>
  <data name="form.goldQuantityRequired" xml:space="preserve"><value>Please enter a valid quantity.</value></data>
  <data name="export.colGoldType" xml:space="preserve"><value>Gold type</value></data>
  <data name="export.colGoldQuantity" xml:space="preserve"><value>Gold (chỉ)</value></data>
```

- [ ] Verify `dotnet build && dotnet test`, commit `feat: gold resx keys (vi/en)`, `git push -u origin feature/gold`.

---

### Task 6: FE — types, api, context, fixture compile fixes

**Files:**
- Create: `src/api/goldApi.ts`, `src/gold/GoldTypesContext.tsx`, `src/utils/gold.ts`
- Modify: `src/api/types.ts`, `src/api/transactionApi.ts` (TransactionPayload), `src/pages/TransactionsPage.test.tsx` + `src/components/TransactionFormModal.test.tsx` (fixtures gain the new nullable fields — `npm run build` type-checks tests)
- Test: `src/gold/GoldTypesContext.test.tsx`

**Interfaces:**
- Produces: `GoldTypeResponse { id, name }`; `GoldSummaryResponse { types: GoldTypeSummaryResponse[], transactions: GoldTransactionResponse[] }`; `TransactionResponse` gains `goldTypeId: string | null; goldTypeName: string | null; goldQuantity: number | null`; `TransactionPayload` gains `goldTypeId: string | null; goldQuantity: number | null`; `getGoldTypes/createGoldType/updateGoldType/deleteGoldType/getGoldSummary`; `GoldTypesProvider` + `useGoldTypes(): { goldTypes, refresh }`; `formatGoldQuantity(quantity: number): string`.

- [ ] **Step 1: Branch** — `cd ../dmoney-tracker-web && git checkout feature/beneficiaries && git pull && git checkout -b feature/gold`
- [ ] **Step 2: Failing test** — `GoldTypesContext.test.tsx` clones `src/beneficiaries/BeneficiariesContext.test.tsx` (Probe component + mocked `getGoldTypes` + mocked i18n): provider loads list, `refresh` refetches. 2 tests suffice.
- [ ] **Step 3: Implement**
  - `types.ts` additions (comment convention "Mirrors …" like the existing types):

```ts
// Mirrors Application/GoldTypes/Data/GoldTypeResponse.cs on the backend.
export interface GoldTypeResponse {
  id: string
  name: string
}

// Mirrors Application/Gold/Data/GoldSummaryResponse.cs on the backend.
export interface GoldTypeSummaryResponse {
  goldTypeId: string
  name: string
  heldQuantity: number
  boughtQuantity: number
  soldQuantity: number
  totalSpent: MoneyResponse
  totalReceived: MoneyResponse
  averageCostPerChi: MoneyResponse
}

export interface GoldTransactionResponse {
  transactionId: string
  date: string // YYYY-MM-DD
  content: string
  goldTypeId: string
  goldTypeName: string
  goldQuantity: number
  credit: MoneyResponse
  debit: MoneyResponse
  pricePerChi: MoneyResponse
}

export interface GoldSummaryResponse {
  types: GoldTypeSummaryResponse[]
  transactions: GoldTransactionResponse[]
}
```

    `TransactionResponse` gains `goldTypeId: string | null`, `goldTypeName: string | null`, `goldQuantity: number | null`; `TransactionPayload` (in `transactionApi.ts`) gains `goldTypeId: string | null`, `goldQuantity: number | null`.
  - `goldApi.ts` mirrors `beneficiaryApi.ts`:

```ts
import { apiClient } from './client'
import type { GoldSummaryResponse, GoldTypeResponse } from './types'

export async function getGoldTypes(): Promise<GoldTypeResponse[]> {
  const { data } = await apiClient.get<GoldTypeResponse[]>('/gold-types')
  return data
}

export async function createGoldType(name: string): Promise<{ id: string }> {
  const { data } = await apiClient.post<{ id: string }>('/gold-types', { name })
  return data
}

export async function updateGoldType(id: string, name: string): Promise<void> {
  await apiClient.put(`/gold-types/${id}`, { name })
}

export async function deleteGoldType(id: string): Promise<void> {
  await apiClient.delete(`/gold-types/${id}`)
}

export async function getGoldSummary(): Promise<GoldSummaryResponse> {
  const { data } = await apiClient.get<GoldSummaryResponse>('/gold/summary')
  return data
}
```

  - `GoldTypesContext.tsx` = copy `BeneficiariesContext.tsx` verbatim with renames (`goldTypes`, `useGoldTypes`, `GoldTypesProvider`, safe default `{ goldTypes: [], refresh: async () => {} }`).
  - `src/utils/gold.ts` (formatMoney pins 0 fraction digits, so quantities need their own formatter):

```ts
const quantityFormatter = new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 })

/** Formats a gold quantity in chỉ (fractions allowed, e.g. 0.5). */
export function formatGoldQuantity(quantity: number): string {
  return quantityFormatter.format(quantity)
}
```

  - Fixture fixes: `TransactionsPage.test.tsx` `tx()` factory, `TransactionFormModal.test.tsx` `baseEditingFixture` AND its inline editing fixture (~lines 354-378) each gain `goldTypeId: null, goldTypeName: null, goldQuantity: null`.
- [ ] **Step 4: Gates + commit** — `npm test && npm run build && npm run lint`; `git commit -am "feat: gold api, types and context"`

---

### Task 7: FE — gold type settings page

**Files:**
- Create: `src/pages/GoldTypeSettingsPage.tsx`, `src/gold/CreateGoldTypeDialog.tsx`
- Modify: `src/App.tsx`, `src/layouts/AppLayout.tsx`
- Test: `src/pages/GoldTypeSettingsPage.test.tsx`

**Interfaces:**
- Consumes: Task 6 (`useGoldTypes`, gold api).
- Produces: route `/app/settings/gold-types`; sidebar settings entry `menu.goldTypes`; `GoldTypesProvider` mounted in `AppLayout`.

- [ ] **Step 1: Failing test** — clone `src/pages/BeneficiarySettingsPage.test.tsx` structure minus the set-default test (3 tests: list — no default badge; rename via `updateGoldType('g-2', …)` + refresh; delete confirm via `deleteGoldType`). Mock `../gold/GoldTypesContext` (`goldTypes: [{ id: 'g-1', name: 'Nhẫn trơn' }, { id: 'g-2', name: 'SJC' }]`), `../api/goldApi`, and i18n directly (same style as the beneficiary test).
- [ ] **Step 2: Implement**
  - `CreateGoldTypeDialog.tsx` = copy `src/beneficiaries/CreateBeneficiaryDialog.tsx` with renames (`createGoldType`, keys `goldTypes.create`/`goldTypes.name`).
  - `GoldTypeSettingsPage.tsx` = copy `BeneficiarySettingsPage.tsx` with renames and WITHOUT set-default: drop the `Star` import, `setDefaultBeneficiary` import, `submitSetDefault`, the default badge block and the Star button. Keys: `goldTypes.title`, `goldTypes.create`, `goldTypes.rename`, `goldTypes.delete`, `goldTypes.deleteConfirm`.
  - `App.tsx`: `<Route path="settings/gold-types" element={<GoldTypeSettingsPage />} />` after the beneficiaries settings route.
  - `AppLayout.tsx`: import `Gem` from lucide-react; `SETTINGS_ITEMS` gains `{ to: '/app/settings/gold-types', key: 'menu.goldTypes', icon: Gem }`; wrap `<GoldTypesProvider>` directly inside `<BeneficiariesProvider>` (open at the top, close at the bottom, matching the flat non-indented provider style there).
- [ ] **Step 3: Gates + commit** — `git commit -am "feat: gold type settings page"`

---

### Task 8: FE — transaction form gold toggle (both directions)

**Files:**
- Modify: `src/components/TransactionFormModal.tsx`, `src/pages/TransactionsPage.tsx` (payload passthrough)
- Test: `src/components/TransactionFormModal.test.tsx`

**Interfaces:**
- Consumes: Task 6 (`useGoldTypes`, payload fields).
- Produces: `TransactionFormValues` gains `goldTypeId: string | null; goldQuantity: number | null`; both null whenever the toggle is off; the block renders for BOTH money-in and money-out (sell = credit + quantity).

- [ ] **Step 1: Failing tests** — add to the modal test file a GoldTypesContext mock next to the beneficiaries one:

```tsx
vi.mock('../gold/GoldTypesContext', () => ({
  useGoldTypes: () => ({
    goldTypes: [
      { id: 'g-ring', name: 'Nhẫn trơn' },
      { id: 'g-sjc', name: 'SJC' },
    ],
    refresh: vi.fn(),
  }),
}))
```

  Tests:
  1. toggle off (default) → submit a valid debit → `goldTypeId: null, goldQuantity: null`; the `form.goldType` combobox is absent.
  2. tick checkbox `form.goldToggle` → pick "Nhẫn trơn" in combobox `form.goldType`, type `0.5` into input labelled `form.goldQuantity`, submit valid debit → `expect.objectContaining({ goldTypeId: 'g-ring', goldQuantity: 0.5 })`.
  3. switch type to money-in (`form.moneyIn` radio), tick the toggle, pick type + quantity `1`, submit valid credit → gold pair present (sell works).
  4. tick the toggle but leave quantity empty → submit → `onSubmit` NOT called (validation error shown).
  5. edit mode: render with `{...baseEditingFixture, goldTypeId: 'g-ring', goldTypeName: 'Nhẫn trơn', goldQuantity: 2}` → checkbox `form.goldToggle` is checked and the quantity input shows `2`.
- [ ] **Step 2: Implement** in `TransactionFormModal.tsx`:
  - Hook + state (next to the beneficiaries ones):

```tsx
  const { goldTypes } = useGoldTypes()
  const [isGold, setIsGold] = useState(false)
  const [goldTypeId, setGoldTypeId] = useState<string | null>(null)
  const [goldQuantityText, setGoldQuantityText] = useState('')
```

  - Hydration effect, editing branch: `setIsGold(editing.goldTypeId !== null)`, `setGoldTypeId(editing.goldTypeId)`, `setGoldQuantityText(editing.goldQuantity !== null ? String(editing.goldQuantity) : '')`. Reset branch: `setIsGold(false)`, `setGoldTypeId(null)`, `setGoldQuantityText('')`.
  - Parse + validation in `validateAndBuild` (decimal input — commas accepted):

```tsx
    const goldQuantity = Number(goldQuantityText.replace(',', '.'))
    if (isGold && goldTypeId === null) nextErrors.goldType = t('form.goldTypeRequired')
    if (isGold && (goldQuantityText === '' || Number.isNaN(goldQuantity) || goldQuantity <= 0)) {
      nextErrors.goldQuantity = t('form.goldQuantityRequired')
    }
```

    Returned values gain: `goldTypeId: isGold ? goldTypeId : null, goldQuantity: isGold ? goldQuantity : null`.
  - `handleSaveAndContinue` clone-flow reset also clears: `setIsGold(false); setGoldTypeId(null); setGoldQuantityText('')`.
  - UI block — placed AFTER the amount input and OUTSIDE the `{type === 'out' && (…)}` block (gold works both directions), using the bordered-checkbox-card pattern of `form.isAdvance`:

```tsx
          <div className="grid gap-2 rounded-lg border px-3 py-2.5">
            <label className="flex items-start gap-2.5">
              <Checkbox
                checked={isGold}
                onCheckedChange={(checked) => {
                  setIsGold(checked === true)
                  if (checked !== true) {
                    setGoldTypeId(null)
                    setGoldQuantityText('')
                  }
                }}
                aria-label={t('form.goldToggle')}
                className="mt-0.5"
              />
              <span className="grid gap-0.5 text-sm">
                <span className="font-medium">{t('form.goldToggle')}</span>
                <span className="text-xs text-muted-foreground">{t('form.goldToggleHint')}</span>
              </span>
            </label>
            {isGold && (
              <div className="grid grid-cols-2 gap-2">
                <div className="grid gap-1.5">
                  <span className="text-xs text-muted-foreground">{t('form.goldType')}</span>
                  <Select
                    value={goldTypeId ?? 'none'}
                    onValueChange={(value) => setGoldTypeId(value === 'none' ? null : value)}
                  >
                    <SelectTrigger aria-label={t('form.goldType')} className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">—</SelectItem>
                      {goldTypes.map((g) => (
                        <SelectItem key={g.id} value={g.id}>{g.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {errors.goldType && <p className="text-xs text-expense">{errors.goldType}</p>}
                </div>
                <div className="grid gap-1.5">
                  <span className="text-xs text-muted-foreground">{t('form.goldQuantity')}</span>
                  <div className="relative">
                    <Input
                      inputMode="decimal"
                      className="pr-9"
                      aria-label={t('form.goldQuantity')}
                      value={goldQuantityText}
                      onChange={(e) => setGoldQuantityText(e.target.value.replace(/[^\d.,]/g, ''))}
                    />
                    <span className="pointer-events-none absolute inset-y-0 right-3 flex items-center text-sm text-muted-foreground">
                      {t('gold.unit')}
                    </span>
                  </div>
                  {errors.goldQuantity && <p className="text-xs text-expense">{errors.goldQuantity}</p>}
                </div>
              </div>
            )}
          </div>
```

  - `TransactionFormValues` interface gains the two fields.
  - `TransactionsPage.handleSubmit` payload adds `goldTypeId: values.goldTypeId, goldQuantity: values.goldQuantity` (after `beneficiaryId`).
- [ ] **Step 3: Gates + commit** — `git commit -am "feat: gold toggle on transaction form"`

---

### Task 9: FE — Gold page (/app/gold)

**Files:**
- Create: `src/pages/GoldPage.tsx`
- Modify: `src/App.tsx`, `src/layouts/AppLayout.tsx`
- Test: `src/pages/GoldPage.test.tsx`

**Interfaces:**
- Consumes: Task 6 (`getGoldSummary`, `formatGoldQuantity`, response types).
- Produces: route `/app/gold`; main-nav entry `menu.gold` (Coins icon).

- [ ] **Step 1: Failing test** — mock `../api/goldApi` and i18n directly (BeneficiarySettingsPage-test style):

```tsx
vi.mock('../api/goldApi', () => ({
  getGoldSummary: vi.fn().mockResolvedValue({
    types: [
      {
        goldTypeId: 'g-1', name: 'Nhẫn trơn', heldQuantity: 2, boughtQuantity: 3, soldQuantity: 1,
        totalSpent: { amount: 31_000_000, currency: 'VND' },
        totalReceived: { amount: 12_000_000, currency: 'VND' },
        averageCostPerChi: { amount: 10_333_333.33, currency: 'VND' },
      },
    ],
    transactions: [
      {
        transactionId: 'tx-1', date: '2026-08-03', content: 'Bán 1 chỉ', goldTypeId: 'g-1',
        goldTypeName: 'Nhẫn trơn', goldQuantity: 1,
        credit: { amount: 12_000_000, currency: 'VND' }, debit: { amount: 0, currency: 'VND' },
        pricePerChi: { amount: 12_000_000, currency: 'VND' },
      },
    ],
  }),
}))
```

  Tests: renders the type card (`await screen.findByText('Nhẫn trơn')`, held shows "2 chỉ"); renders the history row ('Bán 1 chỉ') with the sell badge (`gold.sell`); empty summary (`types: [], transactions: []`) → shows `gold.empty`.
- [ ] **Step 2: Implement** — data-fetching per the DashboardPage pattern (`useCallback` load + `useEffect`), table per its history-table pattern:

```tsx
import { useCallback, useEffect, useState } from 'react'
import dayjs from 'dayjs'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { getApiErrorMessage } from '../api/client'
import { getGoldSummary } from '../api/goldApi'
import type { GoldSummaryResponse } from '../api/types'
import { useI18n } from '../i18n/I18nContext'
import { formatGoldQuantity } from '../utils/gold'
import { formatMoney } from '../utils/money'

export function GoldPage() {
  const { t } = useI18n()
  const [summary, setSummary] = useState<GoldSummaryResponse | null>(null)

  const load = useCallback(async () => {
    try {
      setSummary(await getGoldSummary())
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }, [t])

  useEffect(() => {
    void load()
  }, [load])

  const types = summary?.types ?? []
  const transactions = summary?.transactions ?? []

  return (
    <div className="grid gap-4">
      <h1 className="text-xl font-bold">{t('gold.title')}</h1>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {types.map((type) => (
          <Card key={type.goldTypeId}>
            <CardContent className="grid gap-1.5 p-4">
              <div className="font-semibold">{type.name}</div>
              <div className="text-2xl font-bold">
                {formatGoldQuantity(type.heldQuantity)} {t('gold.unit')}
              </div>
              <div className="grid gap-0.5 text-xs text-muted-foreground">
                <span>
                  {t('gold.bought')}: {formatGoldQuantity(type.boughtQuantity)} · {t('gold.sold')}:{' '}
                  {formatGoldQuantity(type.soldQuantity)}
                </span>
                <span>
                  {t('gold.avgCost')}: {formatMoney(type.averageCostPerChi)}
                </span>
                <span>
                  {t('gold.totalSpent')}: {formatMoney(type.totalSpent)} · {t('gold.totalReceived')}:{' '}
                  {formatMoney(type.totalReceived)}
                </span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          <div className="px-4 pt-4 font-semibold">{t('gold.history')}</div>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t('form.date')}</TableHead>
                <TableHead>{t('form.content')}</TableHead>
                <TableHead>{t('form.goldType')}</TableHead>
                <TableHead className="text-right">{t('form.goldQuantity')}</TableHead>
                <TableHead className="text-right">{t('form.amount')}</TableHead>
                <TableHead className="text-right">{t('gold.pricePerChi')}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {transactions.map((row) => (
                <TableRow key={row.transactionId}>
                  <TableCell>{dayjs(row.date).format('DD/MM/YYYY')}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline">
                        {row.debit.amount > 0 ? t('gold.buy') : t('gold.sell')}
                      </Badge>
                      <span className="font-medium">{row.content}</span>
                    </div>
                  </TableCell>
                  <TableCell>{row.goldTypeName}</TableCell>
                  <TableCell className="text-right">
                    {formatGoldQuantity(row.goldQuantity)} {t('gold.unit')}
                  </TableCell>
                  <TableCell
                    className={
                      row.debit.amount > 0
                        ? 'text-right font-medium text-expense'
                        : 'text-right font-medium text-income'
                    }
                  >
                    {row.debit.amount > 0 ? `−${formatMoney(row.debit)}` : `+${formatMoney(row.credit)}`}
                  </TableCell>
                  <TableCell className="text-right">{formatMoney(row.pricePerChi)}</TableCell>
                </TableRow>
              ))}
              {transactions.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} className="text-center text-muted-foreground">
                    {t('gold.empty')}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
```

  - `App.tsx`: `<Route path="gold" element={<GoldPage />} />` after the transactions route.
  - `AppLayout.tsx`: import `Coins` from lucide-react; `NAV_ITEMS` gains `{ to: '/app/gold', key: 'menu.gold', icon: Coins }` after the transactions entry (mobile nav + breadcrumbs pick it up automatically).
- [ ] **Step 3: Gates + commit** — `git commit -am "feat: gold page with per-type holdings and history"`

---

### Task 10: FE — row chip + Excel columns, push

**Files:**
- Modify: `src/pages/TransactionsPage.tsx`, `src/utils/exportExcel.ts`
- Test: `src/pages/TransactionsPage.test.tsx`

- [ ] **Step 1: Failing test** — extend the page test: one debit fixture gains `goldTypeId: 'g-ring', goldTypeName: 'Nhẫn trơn', goldQuantity: 0.5`; after render, assert the chip text `0,5 chỉ · Nhẫn trơn` is present (note: `formatGoldQuantity` uses vi-VN → decimal COMMA).
- [ ] **Step 2: Implement**
  - Row chip in `TransactionsPage.tsx`, right after the beneficiary chip (yellow — unused by other chips):

```tsx
                      {tx.goldQuantity !== null && (
                        <span className="rounded-md bg-yellow-50 px-1.5 py-0.5 text-yellow-700">
                          {formatGoldQuantity(tx.goldQuantity)} {t('gold.unit')}
                          {tx.goldTypeName ? ` · ${tx.goldTypeName}` : ''}
                        </span>
                      )}
```

    (import `formatGoldQuantity` from `../utils/gold`).
  - `exportExcel.ts`: in BOTH the `rows.map` object and the totals `rows.push` object (every key must appear in both or `json_to_sheet` shifts columns), insert after the beneficiary column:

```ts
    [t('export.colGoldType')]: tx.goldTypeName ?? '',
    [t('export.colGoldQuantity')]: tx.goldQuantity ?? '',
```

    (totals row: both `''`). Widen `!cols` with `{ wch: 14 }, { wch: 10 }` inserted at the matching positions (after the beneficiary `{ wch: 14 }`, before the isAdvance `{ wch: 10 }`).
- [ ] **Step 3: Gates + commit + push** — `git commit -am "feat: gold chip and export columns"`; `git push -u origin feature/gold`

---

### Task 11: E2E, cleanup, docs

- [ ] **Step 1: E2E** — `cd ../dmoney-tracker-orchestrator && docker compose up --build -d`; drive via API: register fresh user → create 2 gold types → buy on default plan + buy on a second plan + sell → `GET /gold/summary` shows cross-plan held/avgCost and zero-row for the untraded type → pair-validation 400s and unknown-type 404 → delete referenced gold type → 409; unlink → 204. Then check the web UI serves (`:8080`) and the Vàng page + settings page load.
- [ ] **Step 2: CLEANUP (mandatory, per memory):** delete every test user created (SQL through `docker exec dmoney-postgres psql`), verify zero `%example.com%` users and no leftover global categories created by the run.
- [ ] **Step 3: Docs** — orchestrator repo: add the contract row to `.claude/skills/dmoney-platform/SKILL.md` (Gold type DTO + optional `goldTypeId`/`goldQuantity` pair on transaction writes, `goldTypeId`/`goldTypeName`/`goldQuantity` on reads; BE `src/Application/GoldTypes/Data/GoldTypeResponse.cs` + `src/Application/Gold/Data/GoldSummaryResponse.cs`, FE `src/api/types.ts`, `src/api/goldApi.ts`, `src/gold/`), and add the `/app/gold` + `/app/settings/gold-types` pages to `.claude/skills/dmoney-web/SKILL.md`. Commit + push orchestrator main.
- [ ] **Step 4:** Confirm both `feature/gold` branches are pushed; offer PR creation via `/create-pr`.
