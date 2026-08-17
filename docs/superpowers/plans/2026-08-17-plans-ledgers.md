# Plans (Sổ) — Separate Ledgers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every transaction belongs to exactly one user-owned "Sổ" (plan/ledger); the web app scopes every screen to a selected plan chosen from a header dropdown.

**Architecture:** New `Plan` aggregate + required `Transaction.PlanId` FK in the .NET backend (Clean Architecture + custom CQRS, EF Core/Npgsql migrations with SQL backfill). React frontend adds a `PlanContext` (selection persisted in localStorage), a header switcher, a settings page, and threads `planId` through every transaction API call.

**Tech Stack:** .NET 10 minimal API, EF Core + Npgsql, xUnit + Shouldly integration tests; Vite + React 19 + TS, Tailwind v4 + shadcn/ui, vitest + Testing Library.

**Spec:** `docs/superpowers/specs/2026-08-16-plans-ledgers-design.md` (orchestrator repo).

## Global Constraints

- Repos: backend `../dmoney-tracker-be`, frontend `../dmoney-tracker-web` — **never commit code in the orchestrator repo** (only docs).
- Branch `feature/plans` off `feature/import-transactions` in BOTH repos.
- Backend gates per task: `dotnet build` + `dotnet test` (run from be repo root). Frontend gates per task: `npm test && npm run build && npm run lint` (from web repo root).
- Default plan name literal: `Sổ chính`; `PlanConstants.NameMaxLength = 100`.
- All user-facing strings via resx keys (`SharedResource.vi.resx` + `SharedResource.en.resx` in be repo); FE `t(key)` falls back to the raw key — resx first.
- Error-code resx convention: key = error code, e.g. `Plans.NotFound`.
- DB naming: tables snake_case (`plans`), columns quoted PascalCase (`"UserId"`), per existing migrations.
- Commit after every green task; never push a failing build.

---

### Task 1: Backend — Plan entity, plans table, default-plan seeding, GET /plans

**Files:**
- Create: `src/Domain/Plans/Plan.cs`, `src/Domain/Plans/PlanConstants.cs`, `src/Domain/Plans/PlanErrors.cs`
- Create: `src/Infrastructure/Plans/PlanConfiguration.cs`
- Create: `src/Application/Plans/Data/PlanResponse.cs`, `src/Application/Plans/GetPlansQuery.cs`, `src/Application/Plans/GetPlansQueryHandler.cs`
- Create: `src/Web.Api/Endpoints/Plans/PlanEndpoints.cs`
- Create: migration `AddPlans` in `src/Infrastructure/Database/Migrations/`
- Modify: `src/Application/Abstractions/Data/IApplicationDbContext.cs`, `src/Infrastructure/Database/ApplicationDbContext.cs`, `src/Application/Users/RegisterUserCommandHandler.cs`
- Test: `tests/Api.IntegrationTests/Plans/PlansEndpointsTests.cs`

**Interfaces:**
- Produces: `Plan.Create(Guid userId, string name, bool isDefault = false) : Result<Plan>`, `Plan.Rename(string name) : Result`, `PlanErrors.{NameRequired,NameTooLong,NotFound,NotEmpty,CannotDeleteDefault}`, `PlanResponse(Guid Id, string Name, bool IsDefault)`, `GET /plans` → `200 [{id,name,isDefault}]` default first, `dbContext.Plans` DbSet.

- [ ] **Step 1: Branch setup (both repos will use it; create be branch now)**

```bash
cd ../dmoney-tracker-be && git checkout feature/import-transactions && git pull && git checkout -b feature/plans
```

- [ ] **Step 2: Write the failing integration test**

`tests/Api.IntegrationTests/Plans/PlansEndpointsTests.cs` (auth helper copied from `Transactions/TransactionsEndpointsTests.cs:12-25`):

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Api.IntegrationTests.Infrastructure;
using Shouldly;

namespace Api.IntegrationTests.Plans;

public sealed class PlansEndpointsTests(ApiTestFactory factory) : IClassFixture<ApiTestFactory>
{
    private async Task<HttpClient> CreateAuthenticatedClientAsync(string email, string username)
    {
        HttpClient client = factory.CreateClient();
        var register = await client.PostAsJsonAsync("/users/register",
            new { email, username, displayName = "Test User", password = "password123" });
        register.StatusCode.ShouldBe(HttpStatusCode.OK);

        var login = await client.PostAsJsonAsync("/users/login",
            new { identifier = email, password = "password123" });
        login.StatusCode.ShouldBe(HttpStatusCode.OK);
        var body = await login.Content.ReadFromJsonAsync<LoginBody>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", body!.Token);
        return client;
    }

    private sealed record LoginBody(string Token);
    internal sealed record PlanBody(Guid Id, string Name, bool IsDefault);

    [Fact]
    public async Task GetPlans_WithoutToken_Returns401()
    {
        (await factory.CreateClient().GetAsync("/plans")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Register_CreatesDefaultPlan()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-default@example.com", "plandefault");

        var response = await client.GetAsync("/plans");
        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        var plans = await response.Content.ReadFromJsonAsync<List<PlanBody>>();
        plans.ShouldNotBeNull();
        plans.Count.ShouldBe(1);
        plans[0].Name.ShouldBe("Sổ chính");
        plans[0].IsDefault.ShouldBeTrue();
    }
}
```

If `LoginBody` already exists as a shared type in the test project, reuse it instead of redeclaring (check `tests/Api.IntegrationTests/GlobalUsings.cs` and existing test files for its home).

- [ ] **Step 3: Run test to verify it fails**

```bash
cd ../dmoney-tracker-be && dotnet test --filter PlansEndpointsTests
```
Expected: FAIL (compile error / 404 — endpoint does not exist).

- [ ] **Step 4: Domain entity**

`src/Domain/Plans/PlanConstants.cs`:

```csharp
namespace Domain.Plans;

public static class PlanConstants
{
    public const int NameMaxLength = 100;

    public const string DefaultPlanName = "Sổ chính";
}
```

`src/Domain/Plans/PlanErrors.cs`:

```csharp
using SharedKernel;

namespace Domain.Plans;

public static class PlanErrors
{
    public static readonly Error NameRequired = Error.Validation(
        "Plans.NameRequired",
        "Please enter a plan name.");

    public static readonly Error NameTooLong = Error.Validation(
        "Plans.NameTooLong",
        $"Plan name must be at most {PlanConstants.NameMaxLength} characters.");

    public static readonly Error NotFound = Error.NotFound(
        "Plans.NotFound",
        "Plan not found.");

    public static readonly Error NotEmpty = Error.Conflict(
        "Plans.NotEmpty",
        "This plan still has transactions and cannot be deleted.");

    public static readonly Error CannotDeleteDefault = Error.Conflict(
        "Plans.CannotDeleteDefault",
        "The default plan cannot be deleted.");
}
```

`src/Domain/Plans/Plan.cs` (pattern: `Domain/Categories/Category.cs`):

```csharp
using SharedKernel;

namespace Domain.Plans;

/// <summary>
/// A separate ledger ("Sổ"): every transaction belongs to exactly one plan and
/// the UI shows one plan at a time. Each user has exactly one default plan.
/// </summary>
public sealed class Plan : AuditedEntity
{
    private Plan() { }

    public Guid UserId { get; private set; }

    public string Name { get; private set; } = string.Empty;

    /// <summary>The auto-created "Sổ chính"; renamable, never deletable.</summary>
    public bool IsDefault { get; private set; }

    public static Result<Plan> Create(Guid userId, string name, bool isDefault = false)
    {
        string trimmed = name?.Trim() ?? string.Empty;
        if (trimmed.Length == 0)
        {
            return Result.Failure<Plan>(PlanErrors.NameRequired);
        }

        if (trimmed.Length > PlanConstants.NameMaxLength)
        {
            return Result.Failure<Plan>(PlanErrors.NameTooLong);
        }

        return new Plan
        {
            Id = Guid.CreateVersion7(),
            UserId = userId,
            Name = trimmed,
            IsDefault = isDefault
        };
    }

    public Result Rename(string name)
    {
        string trimmed = name?.Trim() ?? string.Empty;
        if (trimmed.Length == 0)
        {
            return Result.Failure(PlanErrors.NameRequired);
        }

        if (trimmed.Length > PlanConstants.NameMaxLength)
        {
            return Result.Failure(PlanErrors.NameTooLong);
        }

        Name = trimmed;
        return Result.Success();
    }
}
```

- [ ] **Step 5: EF configuration + DbContext**

`src/Infrastructure/Plans/PlanConfiguration.cs` (pattern: `Infrastructure/Categories/CategoryConfiguration.cs`):

```csharp
using Domain.Plans;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Infrastructure.Plans;

internal sealed class PlanConfiguration : IEntityTypeConfiguration<Plan>
{
    public void Configure(EntityTypeBuilder<Plan> builder)
    {
        builder.ToTable("plans");

        builder.HasKey(p => p.Id);

        builder.Property(p => p.Name)
            .HasMaxLength(PlanConstants.NameMaxLength)
            .IsRequired();

        builder.HasIndex(p => p.UserId);

        builder.Ignore(p => p.DomainEvents);
    }
}
```

Add to `src/Application/Abstractions/Data/IApplicationDbContext.cs` (after `DbSet<Category> Categories`, with `using Domain.Plans;`):

```csharp
    DbSet<Plan> Plans { get; }
```

Add to `src/Infrastructure/Database/ApplicationDbContext.cs` (same spot, same using):

```csharp
    public DbSet<Plan> Plans => Set<Plan>();
```

- [ ] **Step 6: Registration creates the default plan**

In `src/Application/Users/RegisterUserCommandHandler.cs`, after `dbContext.Users.Add(userResult.Value);` and before `SaveChangesAsync` (add `using Domain.Plans;`):

```csharp
        Result<Plan> defaultPlan = Plan.Create(
            userResult.Value.Id, PlanConstants.DefaultPlanName, isDefault: true);
        if (defaultPlan.IsFailure)
        {
            return Result.Failure<Guid>(defaultPlan.Error);
        }

        dbContext.Plans.Add(defaultPlan.Value);
```

- [ ] **Step 7: Query + endpoint**

`src/Application/Plans/Data/PlanResponse.cs`:

```csharp
namespace Application.Plans.Data;

public sealed record PlanResponse(Guid Id, string Name, bool IsDefault);
```

`src/Application/Plans/GetPlansQuery.cs`:

```csharp
using Application.Abstractions.Messaging;
using Application.Plans.Data;

namespace Application.Plans;

public sealed record GetPlansQuery : IQuery<List<PlanResponse>>;
```

`src/Application/Plans/GetPlansQueryHandler.cs`:

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Data;
using Application.Abstractions.Messaging;
using Application.Plans.Data;
using Domain.Users;
using Microsoft.EntityFrameworkCore;
using SharedKernel;

namespace Application.Plans;

internal sealed class GetPlansQueryHandler(
    IApplicationDbContext dbContext,
    IUserContext userContext)
    : IQueryHandler<GetPlansQuery, List<PlanResponse>>
{
    public async Task<Result<List<PlanResponse>>> Handle(
        GetPlansQuery query,
        CancellationToken cancellationToken)
    {
        if (userContext.UserId is not { } userId)
        {
            return Result.Failure<List<PlanResponse>>(UserErrors.Unauthenticated);
        }

        return await dbContext.Plans
            .Where(p => p.UserId == userId)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.Name)
            .Select(p => new PlanResponse(p.Id, p.Name, p.IsDefault))
            .ToListAsync(cancellationToken);
    }
}
```

`src/Web.Api/Endpoints/Plans/PlanEndpoints.cs` (pattern: `Endpoints/Categories/CategoryEndpoints.cs` — one file, one `IEndpoint` class per route; create/update/delete classes come in Tasks 2/5):

```csharp
using Application.Abstractions.Messaging;
using Application.Plans;
using Application.Plans.Data;
using Microsoft.Extensions.Localization;
using SharedKernel;
using Web.Api.Infrastructure;
using Web.Api.Middleware;

namespace Web.Api.Endpoints.Plans;

internal sealed class GetPlans : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapGet("/plans", async (
            IQueryHandler<GetPlansQuery, List<PlanResponse>> handler,
            IStringLocalizer<SharedResource> localizer,
            CancellationToken cancellationToken) =>
        {
            Result<List<PlanResponse>> result = await handler.Handle(
                new GetPlansQuery(), cancellationToken);

            return result.ToHttpResult(localizer, Results.Ok);
        }).RequireAuthorization();
    }
}
```

Handlers are picked up by assembly-scanned DI (same as Categories — verify by checking `Application` DI registration if the handler is not resolved; no manual registration was needed for `GetCategoriesQueryHandler`).

- [ ] **Step 8: Migration — plans table + seed default plan per existing user**

```bash
cd ../dmoney-tracker-be && dotnet ef migrations add AddPlans --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations
```

(If flags differ from repo convention, check `src/Infrastructure/Database/Migrations/` namespaces and the be repo `CLAUDE.md` — migrations must land in `Infrastructure.Database.Migrations`.)

Then hand-edit the generated `Up` to append the seed after `CreateTable`/indexes (pattern: `20260714163057_AddCategoryCodeAndSeed.cs`):

```csharp
            migrationBuilder.Sql("""
                INSERT INTO plans ("Id", "UserId", "Name", "IsDefault", "CreatedAt", "ModifiedAt")
                SELECT gen_random_uuid(), u."Id", 'Sổ chính', TRUE, now(), now()
                FROM users u
                WHERE NOT EXISTS (
                    SELECT 1 FROM plans p WHERE p."UserId" = u."Id" AND p."IsDefault");
                """);
```

Check the generated `CreateTable` column list — if `AuditedEntity` maps different audit column names (compare with the `categories` table migration `20260714160226_AddCategories`), match them in the SQL.

`Down`: the generated `DropTable` is enough.

- [ ] **Step 9: Run tests to verify they pass**

```bash
cd ../dmoney-tracker-be && dotnet build && dotnet test
```
Expected: PASS (both new tests + all existing).

- [ ] **Step 10: Commit**

```bash
cd ../dmoney-tracker-be && git add -A && git commit -m "feat: plan entity, default-plan seeding and GET /plans"
```

---

### Task 2: Backend — POST /plans (create)

**Files:**
- Create: `src/Application/Plans/PlanCommands.cs`, `src/Application/Plans/CreatePlanCommandHandler.cs`
- Modify: `src/Web.Api/Endpoints/Plans/PlanEndpoints.cs`
- Test: `tests/Api.IntegrationTests/Plans/PlansEndpointsTests.cs`

**Interfaces:**
- Consumes: `Plan.Create`, `PlanErrors` (Task 1).
- Produces: `CreatePlanCommand(string Name) : ICommand<Guid>`, `POST /plans {name}` → `201 {id}` at `/plans/{id}`. Also `UpdatePlanCommand(Guid Id, string Name) : ICommand`, `DeletePlanCommand(Guid Id) : ICommand` records (handlers in Task 5).

- [ ] **Step 1: Write the failing tests** (append to `PlansEndpointsTests`)

```csharp
    internal sealed record CreatedBody(Guid Id);

    [Fact]
    public async Task CreatePlan_AppearsAfterDefault()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-create@example.com", "plancreate");

        var create = await client.PostAsJsonAsync("/plans", new { name = "Du lịch Đà Nẵng" });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);
        var created = await create.Content.ReadFromJsonAsync<CreatedBody>();
        created.ShouldNotBeNull();

        var plans = (await (await client.GetAsync("/plans")).Content.ReadFromJsonAsync<List<PlanBody>>())!;
        plans.Count.ShouldBe(2);
        plans[0].IsDefault.ShouldBeTrue();
        plans[1].Id.ShouldBe(created.Id);
        plans[1].Name.ShouldBe("Du lịch Đà Nẵng");
        plans[1].IsDefault.ShouldBeFalse();
    }

    [Fact]
    public async Task CreatePlan_EmptyName_Returns400()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-empty@example.com", "planempty");
        var create = await client.PostAsJsonAsync("/plans", new { name = "  " });
        create.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
    }
```

- [ ] **Step 2: Run to verify FAIL** — `dotnet test --filter PlansEndpointsTests` → 404 on POST.

- [ ] **Step 3: Commands + handler**

`src/Application/Plans/PlanCommands.cs` (all three records now; Update/Delete handlers arrive in Task 5):

```csharp
using Application.Abstractions.Messaging;

namespace Application.Plans;

public sealed record CreatePlanCommand(string Name) : ICommand<Guid>;

public sealed record UpdatePlanCommand(Guid Id, string Name) : ICommand;

public sealed record DeletePlanCommand(Guid Id) : ICommand;
```

`src/Application/Plans/CreatePlanCommandHandler.cs`:

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Data;
using Application.Abstractions.Messaging;
using Domain.Plans;
using Domain.Users;
using SharedKernel;

namespace Application.Plans;

internal sealed class CreatePlanCommandHandler(
    IApplicationDbContext dbContext,
    IUserContext userContext)
    : ICommandHandler<CreatePlanCommand, Guid>
{
    public async Task<Result<Guid>> Handle(
        CreatePlanCommand command,
        CancellationToken cancellationToken)
    {
        if (userContext.UserId is not { } userId)
        {
            return Result.Failure<Guid>(UserErrors.Unauthenticated);
        }

        Result<Plan> plan = Plan.Create(userId, command.Name);
        if (plan.IsFailure)
        {
            return Result.Failure<Guid>(plan.Error);
        }

        dbContext.Plans.Add(plan.Value);
        await dbContext.SaveChangesAsync(cancellationToken);

        return plan.Value.Id;
    }
}
```

Endpoint (append to `PlanEndpoints.cs`):

```csharp
internal sealed class CreatePlan : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapPost("/plans", async (
            CreatePlanCommand command,
            ICommandHandler<CreatePlanCommand, Guid> handler,
            IStringLocalizer<SharedResource> localizer,
            CancellationToken cancellationToken) =>
        {
            Result<Guid> result = await handler.Handle(command, cancellationToken);

            return result.ToHttpResult(
                localizer,
                id => Results.Created($"/plans/{id}", new { id }));
        }).RequireAuthorization();
    }
}
```

- [ ] **Step 4: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: create plan endpoint"`

---

### Task 3: Backend — Transaction.PlanId (column, backfill, write paths, move guard)

**Files:**
- Modify: `src/Domain/Transactions/Transaction.cs`, `src/Domain/Transactions/TransactionErrors.cs`
- Modify: `src/Application/Transactions/CreateTransactionCommand.cs`, `CreateTransactionCommandHandler.cs`, `UpdateTransactionCommand.cs`, `UpdateTransactionCommandHandler.cs`, `ImportTransactionsCommand.cs`, `ImportTransactionsCommandHandler.cs`
- Modify: `src/Web.Api/Endpoints/Transactions/CreateTransaction.cs`, `UpdateTransaction.cs`, `ImportTransactions.cs` (only if they reshape request → command; they bind the command/request directly — adding the field to the command usually suffices; check each)
- Create: migration `AddTransactionPlanId`
- Test: `tests/Api.IntegrationTests/Transactions/TransactionsEndpointsTests.cs` (+ any other test creating transactions, e.g. `StatsEndpointTests.cs`)

**Interfaces:**
- Consumes: `dbContext.Plans`, `PlanErrors.NotFound` (Task 1), `POST /plans` (Task 2, tests).
- Produces: `Transaction.PlanId : Guid`; `Transaction.Create(Guid userId, Guid planId, ...)`; `Transaction.Update(Guid planId, DateOnly date, ...)`; `CreateTransactionCommand`/`UpdateTransactionCommand`/`ImportTransactionsCommand` gain `Guid PlanId`; error `Transactions.PlanMoveLinked`; JSON payloads gain required `planId`.

- [ ] **Step 1: Write the failing tests** (append to `TransactionsEndpointsTests`; also add the shared helper)

```csharp
    private static async Task<Guid> GetDefaultPlanIdAsync(HttpClient client)
    {
        var plans = await (await client.GetAsync("/plans")).Content.ReadFromJsonAsync<List<PlanListBody>>();
        return plans![0].Id;
    }

    private static async Task<Guid> CreatePlanAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/plans", new { name });
        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<CreatedBody>())!.Id;
    }

    internal sealed record PlanListBody(Guid Id, string Name, bool IsDefault);

    [Fact]
    public async Task CreateTransaction_UnknownPlan_Returns404()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-tx404@example.com", "plantx404");
        Guid categoryId = await CreateCategoryAsync(client, "Lương P404", "wallet");

        var create = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-07-05",
            content = "Lương",
            creditAmount = 1_000_000m,
            debitAmount = 0m,
            note = (string?)null,
            categoryId,
            planId = Guid.NewGuid()
        });
        create.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task UpdateTransaction_MovesBetweenPlans()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-move@example.com", "planmove");
        Guid categoryId = await CreateCategoryAsync(client, "Lương Move", "wallet");
        Guid defaultPlan = await GetDefaultPlanIdAsync(client);
        Guid tripPlan = await CreatePlanAsync(client, "Du lịch");

        var create = await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-07-05",
            content = "Vé máy bay",
            creditAmount = 0m,
            debitAmount = 2_000_000m,
            note = (string?)null,
            categoryId,
            planId = defaultPlan
        });
        create.StatusCode.ShouldBe(HttpStatusCode.Created);
        Guid txId = (await create.Content.ReadFromJsonAsync<CreatedBody>())!.Id;

        var update = await client.PutAsJsonAsync($"/transactions/{txId}", new
        {
            date = "2026-07-05",
            content = "Vé máy bay",
            creditAmount = 0m,
            debitAmount = 2_000_000m,
            note = (string?)null,
            categoryId,
            planId = tripPlan
        });
        update.StatusCode.ShouldBe(HttpStatusCode.NoContent);
    }
```

(The move is fully observable once Task 4's scoped GET lands; the isolation assertions live there.)

- [ ] **Step 2: Run to verify FAIL** — `dotnet test --filter TransactionsEndpointsTests` (payloads with `planId` are ignored today, so `CreateTransaction_UnknownPlan_Returns404` fails by returning 201).

- [ ] **Step 3: Entity change**

`src/Domain/Transactions/Transaction.cs`:
- Add property after `UserId`:

```csharp
    /// <summary>The ledger ("Sổ") this transaction belongs to. Required.</summary>
    public Guid PlanId { get; private set; }
```

- `Create(...)`: add `Guid planId` as the second parameter (right after `userId`); set `PlanId = planId` in the object initializer.
- `Update(...)`: add `Guid planId` as the first parameter; assign `PlanId = planId;` alongside the other assignments.

Add to `src/Domain/Transactions/TransactionErrors.cs` (follow the existing `Error.Conflict` style in that file):

```csharp
    public static readonly Error PlanMoveLinked = Error.Conflict(
        "Transactions.PlanMoveLinked",
        "This transaction is linked to an advance or prepaid transaction and cannot move to another plan.");
```

- [ ] **Step 4: Commands + handlers**

- `CreateTransactionCommand`: add `Guid PlanId,` after `Guid? CategoryId,` (before the optional parameters).
- `UpdateTransactionCommand`: same position.
- `ImportTransactionsCommand`: `public sealed record ImportTransactionsCommand(IReadOnlyList<ImportTransactionRow> Rows, Guid PlanId) : ICommand<int>;`

In **all three handlers**, after the `userId` guard, add ownership validation (add `using Domain.Plans;`):

```csharp
        bool planExists = await dbContext.Plans.AnyAsync(
            p => p.Id == command.PlanId && p.UserId == userId, cancellationToken);
        if (!planExists)
        {
            return Result.Failure<Guid>(PlanErrors.NotFound);
        }
```

(`Result.Failure<int>` in the import handler, plain generic to match each handler's return type.)

Pass `command.PlanId` into every `Transaction.Create(userId, command.PlanId, ...)` / `.Update(command.PlanId, ...)` call site (the compiler finds them all — including the per-row `Transaction.Create` inside the import handler).

**Move guard** in `UpdateTransactionCommandHandler` — after loading the existing transaction and before calling `.Update(...)`:

```csharp
        if (transaction.PlanId != command.PlanId)
        {
            bool hasLinks = transaction.ReimbursedByTransactionId is not null
                || transaction.PrepaidTransactionId is not null
                || await dbContext.Transactions.AnyAsync(
                    t => t.ReimbursedByTransactionId == transaction.Id
                         || t.PrepaidTransactionId == transaction.Id,
                    cancellationToken);
            if (hasLinks)
            {
                return Result.Failure(TransactionErrors.PlanMoveLinked);
            }
        }
```

(Use the local variable name the handler already uses for the loaded transaction.)

- [ ] **Step 5: Migration with backfill**

```bash
dotnet ef migrations add AddTransactionPlanId --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations
```

Also add the EF relationship first in `src/Infrastructure/Transactions/` transaction configuration (find the existing `TransactionConfiguration` file):

```csharp
        builder.HasIndex(t => new { t.UserId, t.PlanId });
        builder.HasOne<Domain.Plans.Plan>()
            .WithMany()
            .HasForeignKey(t => t.PlanId)
            .OnDelete(DeleteBehavior.Restrict);
```

Hand-edit the generated migration `Up` so it works on non-empty databases:
1. Change the generated `AddColumn<Guid>` for `PlanId` to `nullable: true` (delete `defaultValue` if scaffolded).
2. After it, backfill + tighten:

```csharp
            migrationBuilder.Sql("""
                UPDATE transactions t
                SET "PlanId" = p."Id"
                FROM plans p
                WHERE p."UserId" = t."UserId" AND p."IsDefault";
                """);

            migrationBuilder.AlterColumn<Guid>(
                name: "PlanId",
                table: "transactions",
                type: "uuid",
                nullable: false,
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);
```

3. Keep the generated index/FK creation **after** the `AlterColumn`. Match the exact generated column/table casing.

- [ ] **Step 6: Fix existing tests to send planId**

Every test payload creating/updating a transaction (in `TransactionsEndpointsTests`, `StatsEndpointTests`, and any other test file the compiler/test run flags) must include `planId = await GetDefaultPlanIdAsync(client)`. Update `ValidPayload(...)` to take a `Guid planId` parameter and thread it through call sites. Run the suite and fix every failure — the failures are the checklist.

- [ ] **Step 7: Verify PASS** — `dotnet build && dotnet test` → all green.

- [ ] **Step 8: Commit** — `git add -A && git commit -m "feat: transactions require a plan; backfill to default plan"`

---

### Task 4: Backend — plan-scoped reads (summary, stats, pickers)

**Files:**
- Modify: `src/Application/Transactions/GetTransactionsByMonthQuery.cs` + handler, `GetDashboardStatsQuery.cs` + handler, `GetOpenAdvancesQuery.cs` + handler, `GetPrepaidCreditsQuery.cs` + handler, `GetCreditsQuery.cs` + handler
- Modify: `src/Web.Api/Endpoints/Transactions/GetTransactionsByMonth.cs`, `GetDashboardStats.cs`, `GetOpenAdvances.cs`, `GetPrepaidCredits.cs`, `GetCredits.cs`
- Test: `tests/Api.IntegrationTests/Transactions/TransactionsEndpointsTests.cs`

**Interfaces:**
- Consumes: Task 3 (`PlanId` on transactions, plan helpers in tests).
- Produces: every read record gains `Guid PlanId` — `GetTransactionsByMonthQuery(string Month, Guid PlanId)`, `GetDashboardStatsQuery(string Month, Guid PlanId)`, `GetOpenAdvancesQuery(Guid? ForTransactionId, Guid PlanId)`, `GetPrepaidCreditsQuery(Guid PlanId)`, `GetCreditsQuery(Guid PlanId)`; endpoints take required `planId` query param (missing → 400).

- [ ] **Step 1: Write the failing isolation test**

```csharp
    [Fact]
    public async Task MonthlySummary_IsScopedToPlan()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-scope@example.com", "planscope");
        Guid categoryId = await CreateCategoryAsync(client, "Lương Scope", "wallet");
        Guid defaultPlan = await GetDefaultPlanIdAsync(client);
        Guid tripPlan = await CreatePlanAsync(client, "Du lịch Scope");

        foreach (var (plan, content, amount) in new[]
                 { (defaultPlan, "Lương", 15_000_000m), (tripPlan, "Khách sạn", 3_000_000m) })
        {
            var create = await client.PostAsJsonAsync("/transactions", new
            {
                date = "2026-07-05",
                content,
                creditAmount = amount,
                debitAmount = 0m,
                note = (string?)null,
                categoryId,
                planId = plan
            });
            create.StatusCode.ShouldBe(HttpStatusCode.Created);
        }

        var summary = await (await client.GetAsync($"/transactions?month=2026-07&planId={tripPlan}"))
            .Content.ReadFromJsonAsync<SummaryBody>();
        summary!.Items.Count.ShouldBe(1);
        summary.Items[0].Content.ShouldBe("Khách sạn");
        summary.TotalCredit.Amount.ShouldBe(3_000_000m);

        // Missing planId is a client error, not "everything".
        (await client.GetAsync("/transactions?month=2026-07")).StatusCode.ShouldBe(HttpStatusCode.BadRequest);
    }
```

- [ ] **Step 2: Run to verify FAIL** (returns both items today; missing-planId returns 200).

- [ ] **Step 3: Implement**

Records — exact new definitions:

```csharp
public sealed record GetTransactionsByMonthQuery(string Month, Guid PlanId) : IQuery<MonthlySummaryResponse>;
public sealed record GetDashboardStatsQuery(string Month, Guid PlanId) : IQuery<DashboardStatsResponse>;
public sealed record GetOpenAdvancesQuery(Guid? ForTransactionId, Guid PlanId) : IQuery<List<AdvanceResponse>>;
public sealed record GetPrepaidCreditsQuery(Guid PlanId) : IQuery<List<PrepaidCreditResponse>>;
public sealed record GetCreditsQuery(Guid PlanId) : IQuery<List<CreditResponse>>;
```

Each handler: after the `userId` guard add the same plan-ownership check as Task 3 (`PlanErrors.NotFound`, typed to the handler's result), then add `&& t.PlanId == query.PlanId` to the main `Where` on `dbContext.Transactions`. In `GetTransactionsByMonthQueryHandler` that is the `monthScope` query (`GetTransactionsByMonthQueryHandler.cs:52-53`); `AttachLinksAsync` needs no filter (links are same-plan by the Task 3 move guard).

Each endpoint: add `Guid planId` to the lambda parameters (non-nullable ⇒ ASP.NET returns 400 when missing) and pass it into the query record, e.g. `GetTransactionsByMonth.cs`:

```csharp
        app.MapGet("/transactions", async (
            string? month,
            Guid planId,
            IQueryHandler<GetTransactionsByMonthQuery, MonthlySummaryResponse> handler,
            ...
            new GetTransactionsByMonthQuery(effectiveMonth, planId),
```

- [ ] **Step 4: Fix existing tests** — every GET of `/transactions`, `/transactions/stats`, `/transactions/advances/open`, `/transactions/prepaid`, `/transactions/credits` in the test suite gains `&planId={...}` (default plan unless the test says otherwise). Run the suite; fix every failure.

- [ ] **Step 5: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: plan-scoped transaction reads"`

---

### Task 5: Backend — rename + delete plan with guards, resx keys

**Files:**
- Create: `src/Application/Plans/UpdatePlanCommandHandler.cs`, `src/Application/Plans/DeletePlanCommandHandler.cs`
- Modify: `src/Web.Api/Endpoints/Plans/PlanEndpoints.cs`
- Modify: `src/Web.Api/Resources/SharedResource.vi.resx`, `SharedResource.en.resx`
- Test: `tests/Api.IntegrationTests/Plans/PlansEndpointsTests.cs`

**Interfaces:**
- Consumes: `PlanCommands.cs` records (Task 2), `Plan.Rename`, `PlanErrors`, `Transaction.PlanId` (Task 3).
- Produces: `PUT /plans/{id} {name}` → 204; `DELETE /plans/{id}` → 204, guarded by `Plans.CannotDeleteDefault` (409) and `Plans.NotEmpty` (409); resx keys for all plan UI labels + error codes.

- [ ] **Step 1: Failing tests**

First add these helpers to `PlansEndpointsTests` (they exist in `TransactionsEndpointsTests` after Task 3 — copy, don't share, matching how the test files already duplicate `CreateAuthenticatedClientAsync`):

```csharp
    private static async Task<Guid> CreatePlanAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/plans", new { name });
        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<CreatedBody>())!.Id;
    }

    private static async Task<Guid> CreateCategoryAsync(HttpClient client, string name, string icon)
    {
        var response = await client.PostAsJsonAsync("/categories", new { name, icon });
        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        return (await response.Content.ReadFromJsonAsync<CreatedBody>())!.Id;
    }
```

Then the tests:

```csharp
    [Fact]
    public async Task RenamePlan_Works()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-rename@example.com", "planrename");
        Guid planId = await CreatePlanAsync(client, "Cũ");

        (await client.PutAsJsonAsync($"/plans/{planId}", new { name = "Mới" }))
            .StatusCode.ShouldBe(HttpStatusCode.NoContent);

        var plans = (await (await client.GetAsync("/plans")).Content.ReadFromJsonAsync<List<PlanBody>>())!;
        plans.ShouldContain(p => p.Name == "Mới");
    }

    [Fact]
    public async Task DeletePlan_Guards()
    {
        HttpClient client = await CreateAuthenticatedClientAsync("plan-delete@example.com", "plandelete");
        Guid defaultPlan = (await (await client.GetAsync("/plans")).Content
            .ReadFromJsonAsync<List<PlanBody>>())![0].Id;

        // Default plan is never deletable.
        (await client.DeleteAsync($"/plans/{defaultPlan}")).StatusCode.ShouldBe(HttpStatusCode.Conflict);

        // A plan with transactions is not deletable.
        Guid full = await CreatePlanAsync(client, "Có giao dịch");
        Guid categoryId = await CreateCategoryAsync(client, "Chi Delete", "tag");
        (await client.PostAsJsonAsync("/transactions", new
        {
            date = "2026-07-05",
            content = "Chi",
            creditAmount = 0m,
            debitAmount = 100_000m,
            note = (string?)null,
            categoryId,
            planId = full
        })).StatusCode.ShouldBe(HttpStatusCode.Created);
        (await client.DeleteAsync($"/plans/{full}")).StatusCode.ShouldBe(HttpStatusCode.Conflict);

        // An empty non-default plan deletes fine.
        Guid empty = await CreatePlanAsync(client, "Trống");
        (await client.DeleteAsync($"/plans/{empty}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);

        // Someone else's plan is a 404.
        HttpClient other = await CreateAuthenticatedClientAsync("plan-other@example.com", "planother");
        (await other.DeleteAsync($"/plans/{full}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }
```

- [ ] **Step 2: Run to verify FAIL** — 404 (endpoints missing).

- [ ] **Step 3: Handlers**

`src/Application/Plans/UpdatePlanCommandHandler.cs`:

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Data;
using Application.Abstractions.Messaging;
using Domain.Plans;
using Domain.Users;
using Microsoft.EntityFrameworkCore;
using SharedKernel;

namespace Application.Plans;

internal sealed class UpdatePlanCommandHandler(
    IApplicationDbContext dbContext,
    IUserContext userContext)
    : ICommandHandler<UpdatePlanCommand>
{
    public async Task<Result> Handle(UpdatePlanCommand command, CancellationToken cancellationToken)
    {
        if (userContext.UserId is not { } userId)
        {
            return Result.Failure(UserErrors.Unauthenticated);
        }

        Plan? plan = await dbContext.Plans
            .FirstOrDefaultAsync(p => p.Id == command.Id && p.UserId == userId, cancellationToken);
        if (plan is null)
        {
            return Result.Failure(PlanErrors.NotFound);
        }

        Result rename = plan.Rename(command.Name);
        if (rename.IsFailure)
        {
            return rename;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Result.Success();
    }
}
```

`src/Application/Plans/DeletePlanCommandHandler.cs` — same shape; after loading:

```csharp
        if (plan.IsDefault)
        {
            return Result.Failure(PlanErrors.CannotDeleteDefault);
        }

        bool hasTransactions = await dbContext.Transactions
            .AnyAsync(t => t.PlanId == plan.Id, cancellationToken);
        if (hasTransactions)
        {
            return Result.Failure(PlanErrors.NotEmpty);
        }

        dbContext.Plans.Remove(plan);
        await dbContext.SaveChangesAsync(cancellationToken);
        return Result.Success();
```

Endpoints (append to `PlanEndpoints.cs`, mirror `UpdateCategory`/`DeleteCategory` incl. the request record `internal sealed record UpdatePlanRequest(string Name);`).

- [ ] **Step 4: resx keys — both files, same keys**

`SharedResource.vi.resx` additions:

```xml
  <data name="Plans.NameRequired" xml:space="preserve"><value>Vui lòng nhập tên sổ.</value></data>
  <data name="Plans.NameTooLong" xml:space="preserve"><value>Tên sổ tối đa 100 ký tự.</value></data>
  <data name="Plans.NotFound" xml:space="preserve"><value>Không tìm thấy sổ.</value></data>
  <data name="Plans.NotEmpty" xml:space="preserve"><value>Sổ vẫn còn giao dịch nên chưa thể xóa.</value></data>
  <data name="Plans.CannotDeleteDefault" xml:space="preserve"><value>Không thể xóa sổ mặc định.</value></data>
  <data name="Transactions.PlanMoveLinked" xml:space="preserve"><value>Giao dịch đang liên kết tạm ứng/trả trước nên không thể chuyển sang sổ khác.</value></data>
  <data name="menu.plans" xml:space="preserve"><value>Sổ</value></data>
  <data name="plans.title" xml:space="preserve"><value>Quản lý sổ</value></data>
  <data name="plans.switcher" xml:space="preserve"><value>Sổ</value></data>
  <data name="plans.create" xml:space="preserve"><value>Tạo sổ mới</value></data>
  <data name="plans.name" xml:space="preserve"><value>Tên sổ</value></data>
  <data name="plans.rename" xml:space="preserve"><value>Đổi tên</value></data>
  <data name="plans.delete" xml:space="preserve"><value>Xóa sổ</value></data>
  <data name="plans.deleteConfirm" xml:space="preserve"><value>Xóa sổ này?</value></data>
  <data name="plans.default" xml:space="preserve"><value>Mặc định</value></data>
  <data name="plans.manage" xml:space="preserve"><value>Quản lý sổ</value></data>
  <data name="plans.created" xml:space="preserve"><value>Đã tạo sổ và chuyển sang sổ mới.</value></data>
  <data name="plans.form" xml:space="preserve"><value>Sổ</value></data>
  <data name="import.targetPlan" xml:space="preserve"><value>Nhập vào sổ</value></data>
```

`SharedResource.en.resx` equivalents:

```xml
  <data name="Plans.NameRequired" xml:space="preserve"><value>Please enter a plan name.</value></data>
  <data name="Plans.NameTooLong" xml:space="preserve"><value>Plan name must be at most 100 characters.</value></data>
  <data name="Plans.NotFound" xml:space="preserve"><value>Plan not found.</value></data>
  <data name="Plans.NotEmpty" xml:space="preserve"><value>This plan still has transactions and cannot be deleted.</value></data>
  <data name="Plans.CannotDeleteDefault" xml:space="preserve"><value>The default plan cannot be deleted.</value></data>
  <data name="Transactions.PlanMoveLinked" xml:space="preserve"><value>This transaction has advance/prepaid links and cannot move to another plan.</value></data>
  <data name="menu.plans" xml:space="preserve"><value>Plans</value></data>
  <data name="plans.title" xml:space="preserve"><value>Manage plans</value></data>
  <data name="plans.switcher" xml:space="preserve"><value>Plan</value></data>
  <data name="plans.create" xml:space="preserve"><value>New plan</value></data>
  <data name="plans.name" xml:space="preserve"><value>Plan name</value></data>
  <data name="plans.rename" xml:space="preserve"><value>Rename</value></data>
  <data name="plans.delete" xml:space="preserve"><value>Delete plan</value></data>
  <data name="plans.deleteConfirm" xml:space="preserve"><value>Delete this plan?</value></data>
  <data name="plans.default" xml:space="preserve"><value>Default</value></data>
  <data name="plans.manage" xml:space="preserve"><value>Manage plans</value></data>
  <data name="plans.created" xml:space="preserve"><value>Plan created and selected.</value></data>
  <data name="plans.form" xml:space="preserve"><value>Plan</value></data>
  <data name="import.targetPlan" xml:space="preserve"><value>Import into plan</value></data>
```

- [ ] **Step 5: Verify PASS** — `dotnet build && dotnet test`.

- [ ] **Step 6: Commit + push branch**

```bash
git add -A && git commit -m "feat: rename/delete plan with guards; plan resx keys" && git push -u origin feature/plans
```

---

### Task 6: Frontend — planApi, types, storage key, PlanContext

**Files:**
- Create: `../dmoney-tracker-web/src/api/planApi.ts`, `src/plans/PlanContext.tsx`
- Modify: `src/api/types.ts`, `src/api/client.ts`
- Test: `src/plans/PlanContext.test.tsx`

**Interfaces:**
- Consumes: BE `GET/POST/PUT/DELETE /plans` (Tasks 1–5).
- Produces: `PlanResponse { id, name, isDefault }`; `getPlans/createPlan/updatePlan/deletePlan`; `STORAGE_KEYS.planId = 'dmoney.plan'`; `PlanProvider` + `usePlans(): { plans, selectedPlanId, selectPlan(id), refresh() }` — `selectedPlanId` is `null` until plans load.

- [ ] **Step 1: Branch setup**

```bash
cd ../dmoney-tracker-web && git checkout feature/import-transactions && git pull && git checkout -b feature/plans
```

- [ ] **Step 2: Write the failing test**

`src/plans/PlanContext.test.tsx`:

```tsx
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { STORAGE_KEYS } from '../api/client'
import { getPlans } from '../api/planApi'
import { PlanProvider, usePlans } from './PlanContext'

vi.mock('../api/planApi', () => ({
  getPlans: vi.fn(),
}))

vi.mock('../i18n/I18nContext', () => ({
  useI18n: () => ({ t: (key: string) => key, lang: 'vi' }),
}))

const PLANS = [
  { id: 'p-default', name: 'Sổ chính', isDefault: true },
  { id: 'p-trip', name: 'Du lịch', isDefault: false },
]

function Probe() {
  const { plans, selectedPlanId, selectPlan } = usePlans()
  return (
    <div>
      <span data-testid="selected">{selectedPlanId ?? 'none'}</span>
      <span data-testid="count">{plans.length}</span>
      <button onClick={() => selectPlan('p-trip')}>go-trip</button>
    </div>
  )
}

describe('PlanContext', () => {
  beforeEach(() => {
    localStorage.clear()
    vi.mocked(getPlans).mockResolvedValue(PLANS)
  })

  it('selects the default plan when nothing is stored', async () => {
    render(<PlanProvider><Probe /></PlanProvider>)
    await waitFor(() => expect(screen.getByTestId('selected')).toHaveTextContent('p-default'))
    expect(screen.getByTestId('count')).toHaveTextContent('2')
  })

  it('keeps a stored valid selection', async () => {
    localStorage.setItem(STORAGE_KEYS.planId, 'p-trip')
    render(<PlanProvider><Probe /></PlanProvider>)
    await waitFor(() => expect(screen.getByTestId('selected')).toHaveTextContent('p-trip'))
  })

  it('falls back to default when the stored plan no longer exists', async () => {
    localStorage.setItem(STORAGE_KEYS.planId, 'p-gone')
    render(<PlanProvider><Probe /></PlanProvider>)
    await waitFor(() => expect(screen.getByTestId('selected')).toHaveTextContent('p-default'))
    expect(localStorage.getItem(STORAGE_KEYS.planId)).toBe('p-default')
  })

  it('persists a manual selection', async () => {
    render(<PlanProvider><Probe /></PlanProvider>)
    await waitFor(() => expect(screen.getByTestId('selected')).toHaveTextContent('p-default'))
    await userEvent.click(screen.getByText('go-trip'))
    expect(screen.getByTestId('selected')).toHaveTextContent('p-trip')
    expect(localStorage.getItem(STORAGE_KEYS.planId)).toBe('p-trip')
  })
})
```

- [ ] **Step 3: Run to verify FAIL** — `npx vitest run src/plans/PlanContext.test.tsx` → module not found.

- [ ] **Step 4: Implement**

`src/api/types.ts` — add:

```ts
export interface PlanResponse {
  id: string
  name: string
  isDefault: boolean
}
```

`src/api/client.ts` — extend `STORAGE_KEYS`:

```ts
  planId: 'dmoney.plan',
```

`src/api/planApi.ts` (pattern: `categoryApi.ts`):

```ts
import { apiClient } from './client'
import type { PlanResponse } from './types'

export async function getPlans(): Promise<PlanResponse[]> {
  const { data } = await apiClient.get<PlanResponse[]>('/plans')
  return data
}

export async function createPlan(name: string): Promise<{ id: string }> {
  const { data } = await apiClient.post<{ id: string }>('/plans', { name })
  return data
}

export async function updatePlan(id: string, name: string): Promise<void> {
  await apiClient.put(`/plans/${id}`, { name })
}

export async function deletePlan(id: string): Promise<void> {
  await apiClient.delete(`/plans/${id}`)
}
```

`src/plans/PlanContext.tsx` (pattern: `CategoriesContext.tsx`):

```tsx
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { toast } from 'sonner'
import type { ReactNode } from 'react'
import { STORAGE_KEYS, getApiErrorMessage } from '../api/client'
import { getPlans } from '../api/planApi'
import { useI18n } from '../i18n/I18nContext'
import type { PlanResponse } from '../api/types'

interface PlansValue {
  plans: PlanResponse[]
  /** Null until the first load finishes; pages must not fetch before it is set. */
  selectedPlanId: string | null
  selectPlan: (id: string) => void
  refresh: () => Promise<void>
}

// Safe default so components (and tests) outside the provider still render.
const PlanContext = createContext<PlansValue>({
  plans: [],
  selectedPlanId: null,
  selectPlan: () => {},
  refresh: async () => {},
})

export function PlanProvider({ children }: { children: ReactNode }) {
  const { t } = useI18n()
  const [plans, setPlans] = useState<PlanResponse[]>([])
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null)

  const selectPlan = useCallback((id: string) => {
    localStorage.setItem(STORAGE_KEYS.planId, id)
    setSelectedPlanId(id)
  }, [])

  const refresh = useCallback(async () => {
    try {
      const loaded = await getPlans()
      setPlans(loaded)
      // Stored selection wins while it still exists; otherwise the default plan.
      const stored = localStorage.getItem(STORAGE_KEYS.planId)
      const valid = loaded.find((p) => p.id === stored) ?? loaded.find((p) => p.isDefault) ?? loaded[0]
      if (valid) {
        localStorage.setItem(STORAGE_KEYS.planId, valid.id)
        setSelectedPlanId(valid.id)
      }
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }, [t])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const value = useMemo(
    () => ({ plans, selectedPlanId, selectPlan, refresh }),
    [plans, selectedPlanId, selectPlan, refresh],
  )

  return <PlanContext.Provider value={value}>{children}</PlanContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePlans(): PlansValue {
  return useContext(PlanContext)
}
```

- [ ] **Step 5: Verify PASS** — `npx vitest run src/plans/PlanContext.test.tsx`, then full gates `npm test && npm run build && npm run lint`.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: plan api and PlanContext with persisted selection"`

---

### Task 7: Frontend — header plan switcher + create-plan dialog

**Files:**
- Create: `src/plans/PlanSwitcher.tsx`, `src/plans/CreatePlanDialog.tsx`
- Modify: `src/layouts/AppLayout.tsx`
- Test: `src/plans/PlanSwitcher.test.tsx`

**Interfaces:**
- Consumes: `usePlans` (Task 6), `createPlan` (Task 6), shadcn `DropdownMenu`/`Dialog`/`Input`/`Button` (vendored in `src/components/ui/`).
- Produces: `<PlanSwitcher />` self-contained header control; `<CreatePlanDialog open onClose onCreated(id) />` reused by the settings page (Task 8).

- [ ] **Step 1: Failing test** — `src/plans/PlanSwitcher.test.tsx`:

```tsx
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PlanSwitcher } from './PlanSwitcher'

const selectPlan = vi.fn()

vi.mock('./PlanContext', () => ({
  usePlans: () => ({
    plans: [
      { id: 'p-default', name: 'Sổ chính', isDefault: true },
      { id: 'p-trip', name: 'Du lịch', isDefault: false },
    ],
    selectedPlanId: 'p-default',
    selectPlan,
    refresh: vi.fn(),
  }),
}))

vi.mock('../i18n/I18nContext', () => ({
  useI18n: () => ({ t: (key: string) => key, lang: 'vi' }),
}))

vi.mock('react-router-dom', () => ({
  useNavigate: () => vi.fn(),
}))

describe('PlanSwitcher', () => {
  it('shows the selected plan and switches on pick', async () => {
    render(<PlanSwitcher />)
    expect(screen.getByRole('button', { name: /Sổ chính/ })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: /Sổ chính/ }))
    await userEvent.click(await screen.findByText('Du lịch'))
    expect(selectPlan).toHaveBeenCalledWith('p-trip')
  })

  it('offers create and manage entries', async () => {
    render(<PlanSwitcher />)
    await userEvent.click(screen.getByRole('button', { name: /Sổ chính/ }))
    expect(await screen.findByText('plans.create')).toBeInTheDocument()
    expect(screen.getByText('plans.manage')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify FAIL** — module not found.

- [ ] **Step 3: Implement**

`src/plans/CreatePlanDialog.tsx`:

```tsx
import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { getApiErrorMessage } from '../api/client'
import { createPlan } from '../api/planApi'
import { useI18n } from '../i18n/I18nContext'

interface Props {
  open: boolean
  onClose: () => void
  /** Called with the new plan id after a successful create. */
  onCreated: (id: string) => Promise<void> | void
}

export function CreatePlanDialog({ open, onClose, onCreated }: Props) {
  const { t } = useI18n()
  const [name, setName] = useState('')
  const [saving, setSaving] = useState(false)

  const submit = async () => {
    if (!name.trim()) return
    setSaving(true)
    try {
      const { id } = await createPlan(name.trim())
      toast.success(t('plans.created'))
      setName('')
      await onCreated(id)
      onClose()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('plans.create')}</DialogTitle>
        </DialogHeader>
        <div className="grid gap-1.5">
          <span className="text-xs text-muted-foreground">{t('plans.name')}</span>
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && void submit()}
            autoFocus
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{t('summary.cancel')}</Button>
          <Button disabled={saving || !name.trim()} onClick={() => void submit()}>
            {t('plans.create')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
```

(If `src/components/ui/dialog.tsx` is missing, vendor it: `npx shadcn@latest add -y dialog`.)

`src/plans/PlanSwitcher.tsx`:

```tsx
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BookOpen, Check, ChevronDown, Plus, Settings2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { useI18n } from '../i18n/I18nContext'
import { CreatePlanDialog } from './CreatePlanDialog'
import { usePlans } from './PlanContext'

export function PlanSwitcher() {
  const { t } = useI18n()
  const { plans, selectedPlanId, selectPlan, refresh } = usePlans()
  const navigate = useNavigate()
  const [creating, setCreating] = useState(false)

  const selected = plans.find((p) => p.id === selectedPlanId)

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" className="h-9 gap-2 px-3 text-[12.5px] font-medium">
            <BookOpen className="h-4 w-4 text-primary" />
            <span className="max-w-[140px] truncate">{selected?.name ?? t('plans.switcher')}</span>
            <ChevronDown className="h-3 w-3 text-muted-foreground" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-[200px]">
          {plans.map((plan) => (
            <DropdownMenuItem key={plan.id} onClick={() => selectPlan(plan.id)}>
              <Check className={cn('mr-2 h-4 w-4', plan.id === selectedPlanId ? 'opacity-100' : 'opacity-0')} />
              <span className="min-w-0 flex-1 truncate">{plan.name}</span>
              {plan.isDefault && (
                <span className="ml-2 rounded bg-zinc-100 px-1.5 py-0.5 text-[10px] text-muted-foreground">
                  {t('plans.default')}
                </span>
              )}
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setCreating(true)}>
            <Plus className="mr-2 h-4 w-4" />
            {t('plans.create')}
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => navigate('/app/settings/plans')}>
            <Settings2 className="mr-2 h-4 w-4" />
            {t('plans.manage')}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <CreatePlanDialog
        open={creating}
        onClose={() => setCreating(false)}
        onCreated={async (id) => {
          await refresh()
          selectPlan(id)
        }}
      />
    </>
  )
}
```

`src/layouts/AppLayout.tsx`:
- Wrap the tree with the provider: `<CategoriesProvider><PlanProvider> … </PlanProvider></CategoriesProvider>` (import `PlanProvider` from `../plans/PlanContext`). **Note:** `PlanSwitcher` must render *inside* `PlanProvider`.
- In the header controls div (`AppLayout.tsx:150` `<div className="flex items-center gap-3.5">`), add `<PlanSwitcher />` as the first child (import from `../plans/PlanSwitcher`).

- [ ] **Step 4: Verify PASS** — `npx vitest run src/plans`, then full gates.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: header plan switcher with create dialog"`

---

### Task 8: Frontend — plans settings page + route

**Files:**
- Create: `src/pages/PlanSettingsPage.tsx`
- Modify: `src/App.tsx`, `src/layouts/AppLayout.tsx`
- Test: `src/pages/PlanSettingsPage.test.tsx`

**Interfaces:**
- Consumes: `usePlans`, `planApi.updatePlan/deletePlan`, `CreatePlanDialog` (Tasks 6–7).
- Produces: route `/app/settings/plans`; sidebar entry `menu.plans`.

- [ ] **Step 1: Failing test** — `src/pages/PlanSettingsPage.test.tsx`:

```tsx
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { deletePlan, updatePlan } from '../api/planApi'
import { PlanSettingsPage } from './PlanSettingsPage'

const refresh = vi.fn()

vi.mock('../api/planApi', () => ({
  createPlan: vi.fn(),
  updatePlan: vi.fn().mockResolvedValue(undefined),
  deletePlan: vi.fn().mockResolvedValue(undefined),
}))

vi.mock('../plans/PlanContext', () => ({
  usePlans: () => ({
    plans: [
      { id: 'p-default', name: 'Sổ chính', isDefault: true },
      { id: 'p-trip', name: 'Du lịch', isDefault: false },
    ],
    selectedPlanId: 'p-default',
    selectPlan: vi.fn(),
    refresh,
  }),
}))

vi.mock('../i18n/I18nContext', () => ({
  useI18n: () => ({ t: (key: string) => key, lang: 'vi' }),
}))

describe('PlanSettingsPage', () => {
  it('lists plans and marks the default one undeletable', () => {
    render(<PlanSettingsPage />)
    expect(screen.getByText('Sổ chính')).toBeInTheDocument()
    expect(screen.getByText('plans.default')).toBeInTheDocument()
    // Only the non-default plan has a delete button.
    expect(screen.getAllByRole('button', { name: /plans.delete/ })).toHaveLength(1)
  })

  it('renames a plan', async () => {
    render(<PlanSettingsPage />)
    await userEvent.click(screen.getAllByRole('button', { name: /plans.rename/ })[1])
    const input = await screen.findByDisplayValue('Du lịch')
    await userEvent.clear(input)
    await userEvent.type(input, 'Du lịch hè{Enter}')
    expect(updatePlan).toHaveBeenCalledWith('p-trip', 'Du lịch hè')
    expect(refresh).toHaveBeenCalled()
  })

  it('deletes after confirm', async () => {
    render(<PlanSettingsPage />)
    await userEvent.click(screen.getByRole('button', { name: /plans.delete/ }))
    await userEvent.click(await screen.findByText('summary.delete'))
    expect(deletePlan).toHaveBeenCalledWith('p-trip')
  })
})
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Implement `src/pages/PlanSettingsPage.tsx`** (layout/idiom: follow `CategorySettingsPage.tsx` — read it first and mirror its Card/list markup):

```tsx
import { useState } from 'react'
import { Pencil, Plus, Trash2 } from 'lucide-react'
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
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { getApiErrorMessage } from '../api/client'
import { deletePlan, updatePlan } from '../api/planApi'
import type { PlanResponse } from '../api/types'
import { useI18n } from '../i18n/I18nContext'
import { CreatePlanDialog } from '../plans/CreatePlanDialog'
import { usePlans } from '../plans/PlanContext'

export function PlanSettingsPage() {
  const { t } = useI18n()
  const { plans, refresh, selectPlan } = usePlans()
  const [creating, setCreating] = useState(false)
  const [editing, setEditing] = useState<PlanResponse | null>(null)
  const [editName, setEditName] = useState('')
  const [deleting, setDeleting] = useState<PlanResponse | null>(null)

  const submitRename = async () => {
    if (!editing || !editName.trim()) return
    try {
      await updatePlan(editing.id, editName.trim())
      setEditing(null)
      await refresh()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }

  const submitDelete = async () => {
    if (!deleting) return
    try {
      await deletePlan(deleting.id)
      setDeleting(null)
      await refresh()
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }

  return (
    <div className="grid gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold">{t('plans.title')}</h1>
        <Button onClick={() => setCreating(true)}>
          <Plus className="mr-1 h-4 w-4" />
          {t('plans.create')}
        </Button>
      </div>

      <Card>
        <CardContent className="divide-y p-0">
          {plans.map((plan) => (
            <div key={plan.id} className="flex items-center gap-3 px-4 py-3">
              {editing?.id === plan.id ? (
                <Input
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && void submitRename()}
                  autoFocus
                  className="max-w-xs"
                />
              ) : (
                <span className="min-w-0 flex-1 truncate font-medium">{plan.name}</span>
              )}
              {plan.isDefault && (
                <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-[10.5px] text-muted-foreground">
                  {t('plans.default')}
                </span>
              )}
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-muted-foreground hover:text-foreground"
                aria-label={`${t('plans.rename')} ${plan.name}`}
                onClick={() => {
                  setEditing(plan)
                  setEditName(plan.name)
                }}
              >
                <Pencil className="h-4 w-4" />
              </Button>
              {!plan.isDefault && (
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-muted-foreground hover:bg-expense/10 hover:text-expense"
                  aria-label={`${t('plans.delete')} ${plan.name}`}
                  onClick={() => setDeleting(plan)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              )}
            </div>
          ))}
        </CardContent>
      </Card>

      <CreatePlanDialog
        open={creating}
        onClose={() => setCreating(false)}
        onCreated={async (id) => {
          await refresh()
          selectPlan(id)
        }}
      />

      <AlertDialog open={deleting !== null} onOpenChange={(next) => !next && setDeleting(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('plans.deleteConfirm')}</AlertDialogTitle>
            <AlertDialogDescription>{deleting?.name}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('summary.cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={() => void submitDelete()}>{t('summary.delete')}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
```

`src/App.tsx` — add route (import the page):

```tsx
                <Route path="settings/plans" element={<PlanSettingsPage />} />
```

`src/layouts/AppLayout.tsx` — add to `SETTINGS_ITEMS` (import `BookOpen` from lucide-react):

```tsx
  { to: '/app/settings/plans', key: 'menu.plans', icon: BookOpen },
```

- [ ] **Step 4: Verify PASS** — targeted vitest, then full gates.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: plan settings page with rename and guarded delete"`

---

### Task 9: Frontend — thread planId through every transaction call

**Files:**
- Modify: `src/api/transactionApi.ts`, `src/pages/TransactionsPage.tsx`, `src/pages/DashboardPage.tsx`, `src/components/ImportTransactionsDialog.tsx`, `src/components/TransactionFormModal.tsx`
- Test: `src/pages/TransactionsPage.test.tsx` (extend the existing file)

**Interfaces:**
- Consumes: `usePlans().selectedPlanId` (Task 6); BE query params/body (Tasks 3–4).
- Produces: `getMonthlySummary(month, planId)`, `getDashboardStats(month, planId)`, `getOpenAdvances(planId, forTransaction?)`, `getCredits(planId)`, `getPrepaidCredits(planId)`, `importTransactions(rows, planId)`, `TransactionPayload.planId: string`.

- [ ] **Step 1: Failing test** — extend `src/pages/TransactionsPage.test.tsx`: add a `vi.mock('../plans/PlanContext', ...)` returning `selectedPlanId: 'p-default'`, and assert the call signature:

```tsx
vi.mock('../plans/PlanContext', () => ({
  usePlans: () => ({
    plans: [
      { id: 'p-default', name: 'Sổ chính', isDefault: true },
      { id: 'p-trip', name: 'Du lịch', isDefault: false },
    ],
    selectedPlanId: 'p-default',
    selectPlan: vi.fn(),
    refresh: vi.fn(),
  }),
}))
```

New test inside the describe block:

```tsx
  it('loads the summary scoped to the selected plan', async () => {
    vi.mocked(getMonthlySummary).mockResolvedValue({
      items: [],
      totalCredit: { amount: 0, currency: 'VND' },
      totalDebit: { amount: 0, currency: 'VND' },
      balance: { amount: 0, currency: 'VND' },
    })
    render(
      <I18nProvider>
        <TransactionsPage />
      </I18nProvider>,
    )
    await waitFor(() =>
      expect(getMonthlySummary).toHaveBeenCalledWith(dayjs().format('YYYY-MM'), 'p-default'),
    )
  })
```

(Import `waitFor` from `@testing-library/react`.)

- [ ] **Step 2: Run to verify FAIL** — called with one argument today.

- [ ] **Step 3: Implement**

`src/api/transactionApi.ts` — new signatures (exact):

```ts
export async function getMonthlySummary(month: string, planId: string): Promise<MonthlySummaryResponse> {
  const { data } = await apiClient.get<MonthlySummaryResponse>('/transactions', { params: { month, planId } })
  return data
}

export async function getDashboardStats(month: string, planId: string): Promise<DashboardStatsResponse> {
  const { data } = await apiClient.get<DashboardStatsResponse>('/transactions/stats', { params: { month, planId } })
  return data
}

export async function getOpenAdvances(planId: string, forTransaction?: string): Promise<AdvanceResponse[]> {
  const { data } = await apiClient.get<AdvanceResponse[]>('/transactions/advances/open', {
    params: forTransaction ? { planId, forTransaction } : { planId },
  })
  return data
}

export async function getCredits(planId: string): Promise<CreditResponse[]> {
  const { data } = await apiClient.get<CreditResponse[]>('/transactions/credits', { params: { planId } })
  return data
}

export async function getPrepaidCredits(planId: string): Promise<PrepaidCreditResponse[]> {
  const { data } = await apiClient.get<PrepaidCreditResponse[]>('/transactions/prepaid', { params: { planId } })
  return data
}

export async function importTransactions(rows: ImportRowPayload[], planId: string): Promise<{ imported: number }> {
  const { data } = await apiClient.post<{ imported: number }>('/transactions/import', { rows, planId })
  return data
}
```

`TransactionPayload` — add `planId: string` after `subCategoryId`.

`src/pages/TransactionsPage.tsx`:
- `const { selectedPlanId } = usePlans()` (import from `../plans/PlanContext`).
- `load` waits for the plan and passes it:

```ts
  const load = useCallback(async () => {
    if (!selectedPlanId) return
    try {
      setSummary(await getMonthlySummary(monthKey, selectedPlanId))
    } catch (error) {
      toast.error(getApiErrorMessage(error, t('error.network')))
    }
  }, [monthKey, selectedPlanId, t])
```

- `handleSubmit` payload gains `planId: values.planId ?? selectedPlanId!` (`values.planId` arrives in Task 10; until then use `selectedPlanId!` — the compiler will force the final form).

`src/pages/DashboardPage.tsx` — same pattern: pull `selectedPlanId`, guard `if (!selectedPlanId) return`, pass to both `getDashboardStats(statsKey, selectedPlanId)` and `getMonthlySummary(monthKey, selectedPlanId)` (`DashboardPage.tsx:37-38`), and add `selectedPlanId` to the effect/callback dependency array so switching plans refetches.

`src/components/ImportTransactionsDialog.tsx`:
- `const { plans, selectedPlanId } = usePlans()`; guard the save handler with `if (!selectedPlanId) return`; call `importTransactions(parsed.valid, selectedPlanId)`.
- In the dialog body, above the file input, show the target: 

```tsx
<p className="text-xs text-muted-foreground">
  {t('import.targetPlan')}: <strong>{plans.find((p) => p.id === selectedPlanId)?.name}</strong>
</p>
```

`src/components/TransactionFormModal.tsx` — the three picker effects (`TransactionFormModal.tsx:168,179,189`) call `getOpenAdvances(editing?.id)`, `getCredits()`, `getPrepaidCredits()`. Add `const { selectedPlanId } = usePlans()` and change to `getOpenAdvances(selectedPlanId!, editing?.id)`, `getCredits(selectedPlanId!)`, `getPrepaidCredits(selectedPlanId!)` with a `if (!selectedPlanId) return` guard in each effect; add it to their dependency arrays. Existing modal tests mock the api module, so they stay green; add `vi.mock('../plans/PlanContext', ...)` to `TransactionFormModal.test.tsx` (same mock shape as above) since the component now consumes it.

- [ ] **Step 4: Verify PASS** — full gates: `npm test && npm run build && npm run lint` (the build type-checks every call site — fix all compiler errors it finds).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: scope all transaction calls to the selected plan"`

---

### Task 10: Frontend — move transaction between plans from the edit form

**Files:**
- Modify: `src/components/TransactionFormModal.tsx`, `src/pages/TransactionsPage.tsx`
- Test: `src/components/TransactionFormModal.test.tsx`

**Interfaces:**
- Consumes: `usePlans` (already inside the modal after Task 9), `TransactionFormValues`.
- Produces: `TransactionFormValues.planId: string | null` — `null` on create (page substitutes `selectedPlanId`), the picked plan id when editing.

- [ ] **Step 1: Failing test** — append to `TransactionFormModal.test.tsx` (with the PlanContext mock from Task 9 in place):

```tsx
  it('lets an edited transaction pick another plan', async () => {
    const onSubmit = vi.fn()
    render(
      <Wrapper>
        <TransactionFormModal
          open
          editing={{ ...baseEditingFixture }}
          submitting={false}
          onSubmit={onSubmit}
          onCancel={() => {}}
        />
      </Wrapper>,
    )

    // Plan select only renders in edit mode, preselected to the current plan.
    await userEvent.click(await screen.findByRole('combobox', { name: 'plans.form' }))
    await userEvent.click(await screen.findByRole('option', { name: 'Du lịch' }))
    await userEvent.click(screen.getByRole('button', { name: 'summary.submit' }))

    await waitFor(() => expect(onSubmit).toHaveBeenCalled())
    expect(onSubmit.mock.calls[0][0].planId).toBe('p-trip')
  })
```

`baseEditingFixture`: reuse/adapt however existing edit-mode tests in that file build their `editing` prop (copy the closest existing fixture; it must include a valid amount, content, category so submit passes validation). If no edit-mode fixture exists, build a minimal `TransactionResponse` (all fields, like the `tx()` helper in `src/pages/TransactionsPage.test.tsx`).

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Implement**

In `TransactionFormModal.tsx`:
- Add `planId: string | null` to `TransactionFormValues`.
- Form state: initialize `planId` to `editing ? selectedPlanId : null` when the dialog opens (follow how the other fields hydrate from `editing` in the existing open/reset effect).
- Render, only when `editing` is set, a labelled Select in the form grid (place it next to the date field; follow the existing shadcn Select usage in the file):

```tsx
{editing && (
  <div className="grid gap-1.5">
    <span className="text-xs text-muted-foreground">{t('plans.form')}</span>
    <Select
      value={values.planId ?? selectedPlanId ?? undefined}
      onValueChange={(value) => setValues((prev) => ({ ...prev, planId: value }))}
    >
      <SelectTrigger aria-label={t('plans.form')} className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {plans.map((plan) => (
          <SelectItem key={plan.id} value={plan.id}>
            {plan.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  </div>
)}
```

(Adapt `values`/`setValues` to the file's actual state naming — read the file first; it may use individual `useState`s, in which case add `const [planId, setPlanId] = useState<string | null>(null)` and include it in the submitted values.)

In `TransactionsPage.tsx` `handleSubmit`, the Task 9 placeholder becomes:

```ts
      planId: values.planId ?? selectedPlanId!,
```

On a successful move (`editing && values.planId && values.planId !== selectedPlanId`), the reloaded summary simply no longer contains the row — no extra handling needed.

- [ ] **Step 4: Verify PASS** — full gates.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: move transactions between plans from the edit form"`

---

### Task 11: End-to-end verification, docs, push

**Files:**
- Modify (orchestrator): `.claude/skills/dmoney-platform/SKILL.md` (cross-repo contracts table), `.claude/skills/dmoney-web/SKILL.md` (pages list)

**Interfaces:** none — verification + bookkeeping.

- [ ] **Step 1: Full-stack run**

```bash
cd ../dmoney-tracker-orchestrator && docker compose up --build -d
```

Wait for healthy, then drive the real flow (superpowers:verification-before-completion — evidence, not assumptions):
1. Register a fresh user → header shows "Sổ chính".
2. Create transactions in "Sổ chính"; create plan "Du lịch" from the header (+ auto-switch); add a transaction there.
3. Switch between plans — dashboard + transactions list + Excel export change accordingly; totals match each plan only.
4. Edit the trip transaction → move it to "Sổ chính" → it disappears from "Du lịch".
5. Import a small CSV → rows land in the currently selected plan (dialog shows the plan name).
6. Settings → plans: rename works; delete blocked for default and non-empty; empty plan deletes.
7. Reload the page → selection persists; log out/in → still correct.

- [ ] **Step 2: Update orchestrator skill docs**

In `.claude/skills/dmoney-platform/SKILL.md`, add a row to the cross-repo contracts table:

```markdown
| Plan (Sổ) DTO + planId param on all transaction APIs | `src/Application/Plans/Data/PlanResponse.cs` | `src/api/types.ts` (`PlanResponse`), `src/api/planApi.ts` |
```

In `.claude/skills/dmoney-web/SKILL.md`, extend the pages line with `/app/settings/plans` and mention the header plan switcher (`src/plans/`).

- [ ] **Step 3: Push both feature branches**

```bash
cd ../dmoney-tracker-be && git push -u origin feature/plans
cd ../dmoney-tracker-web && git push origin feature/plans
cd ../dmoney-tracker-orchestrator && git add -A && git commit -m "docs: plans implementation plan + skill contract updates" && git push origin main
```

- [ ] **Step 4: Offer `/create-pr be` and `/create-pr web` to the user.**
