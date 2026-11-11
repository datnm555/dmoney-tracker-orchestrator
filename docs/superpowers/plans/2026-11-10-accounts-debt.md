# Accounts & Debt (Tài khoản & Nợ) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Tài khoản & Nợ" page where the owner registers bank accounts / overdraft / credit cards and records hand-entered balance snapshots, showing cash on hand, total debt, available credit, overdraft interest per month and card payments due soon.

**Architecture:** Two new per-user aggregates in the backend (`Account`, `AccountSnapshot`) with plain CRUD endpoints; `GET /accounts` embeds each account's latest snapshot. All totals/due logic is derived client-side in pure, unit-tested helpers (`src/utils/accounts.ts`). No link to transactions.

**Tech Stack:** unchanged (.NET 10 Clean Architecture + custom CQRS + EF Core/Npgsql; React 19 + Tailwind v4 + shadcn/ui + vitest).

**Spec:** `docs/superpowers/specs/2026-11-10-accounts-debt-design.md` (orchestrator repo) — field rules, routes, response records, error codes and resx keys/values there are verbatim requirements.

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`, both branch `feature/accounts` from up-to-date `main`. Never commit product code in the orchestrator repo.
- Follow the Banks feature as the template for every layer (BE: `src/Domain/Banks`, `src/Application/Banks`, `src/Infrastructure/Banks/BankConfiguration.cs`, `src/Web.Api/Endpoints/Banks/BankEndpoints.cs`, `tests/Api.IntegrationTests/Banks/BanksEndpointsTests.cs`; FE: `src/api/bankApi.ts`, `src/pages/BankSettingsPage.tsx`).
- Handlers `internal sealed`, explicit registration in `src/Application/DependencyInjection.cs`; `DbSet`s added to `IApplicationDbContext` + `ApplicationDbContext`.
- Every PUT uses an explicit request record that hand-threads EVERY field; each gets an update-path integration test (historical failure mode).
- Migration: `dotnet dotnet-ef migrations add AddAccounts --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations` (scaffold untouched). Tables `accounts`, `account_snapshots`; money `numeric(18,2)`, rate `numeric(5,2)`; snapshot FK cascade.
- Money in responses uses the existing `MoneyResponse(amount, currency)` with `Money.DefaultCurrency`.
- i18n has NO placeholders — compose phrases in the web (spec "i18n" note). resx keys in both files, same order, identical key sets; `ResourcesEndpointTests` must assert the new keys.
- Never store full account numbers anywhere (code, tests, docs, seed) — tests use fake 4-digit values.
- Gates — BE: `dotnet build DMoney.slnx` (0 warnings) && `dotnet test DMoney.slnx`; FE: `npm test && npm run build && npm run lint` (no new warnings; baseline 9). Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push after each green task; never force-push.

## Review Focus

- Two snapshots on the same `Date` → `latestSnapshot` is the later-created one (BE test in Task 2).
- Account with no snapshot → excluded from all totals, card shows `accounts.noSnapshot`, no crash (FE test in Task 4).
- Debt account with no credit limit → contributes to total debt but not to available credit; no usage bar (FE util test in Task 4).
- Owed above the limit (over-limit) → available credit clamps to 0, never negative (FE util test in Task 4).
- Due date today (`daysLeft = 0`) → listed, urgent, label `accounts.dueToday`; due yesterday or `statementPaid` or amount 0 → not listed (FE util test in Task 4).

---

### Task 1: BE — Account aggregate + CRUD

**Files:** Create `src/Domain/Accounts/{Account.cs,AccountTypes.cs,AccountConstants.cs,AccountErrors.cs}`, `src/Application/Accounts/{AccountCommands.cs,GetAccountsQuery.cs,GetAccountsQueryHandler.cs,CreateAccountCommandHandler.cs,UpdateAccountCommandHandler.cs,DeleteAccountCommandHandler.cs,Data/AccountResponse.cs}`, `src/Infrastructure/Accounts/AccountConfiguration.cs`, `src/Web.Api/Endpoints/Accounts/AccountEndpoints.cs`, `tests/Api.IntegrationTests/Accounts/AccountsEndpointsTests.cs`; Modify DI, DbContext interface/impl, resx (error messages for `Accounts.*` used here).

**Interfaces — Produces:**

```csharp
public static class AccountTypes {
    public const string Checking = "checking", Overdraft = "overdraft", CreditCard = "credit_card",
        Ewallet = "ewallet", Cash = "cash";
    public static readonly IReadOnlyList<string> All = [Checking, Ewallet, Cash, Overdraft, CreditCard];
    public static bool IsValid(string type) => All.Contains(type, StringComparer.Ordinal);
}
public sealed record CreateAccountCommand(string Name, string Type, string? LastDigits = null,
    decimal? CreditLimit = null, int? StatementDay = null, int? DueDay = null,
    decimal? InterestRatePercent = null) : ICommand<Guid>;
public sealed record UpdateAccountCommand(Guid Id, string Name, string Type, string? LastDigits = null,
    decimal? CreditLimit = null, int? StatementDay = null, int? DueDay = null,
    decimal? InterestRatePercent = null) : ICommand;
public sealed record DeleteAccountCommand(Guid Id) : ICommand;
public sealed record GetAccountsQuery : IQuery<List<AccountResponse>>;
// AccountResponse / AccountSnapshotResponse exactly as in the spec (LatestSnapshot null until Task 2).
```

Ordering of `GET /accounts`: index of `Type` in `AccountTypes.All` (money types first, then overdraft, then credit_card), then `Name`.

- [ ] Write failing integration tests: create → GET lists it with every field; PUT changes every field (update-path) and GET reflects it; DELETE → gone; ordering by type group then name; validation → 400 with codes `Accounts.NameRequired` (blank), `Accounts.NameTooLong` (101 chars), `Accounts.InvalidType` ("savings"), `Accounts.InvalidLastDigits` ("12a4", "123"), `Accounts.InvalidDay` (0, 32), `Accounts.NegativeAmount` (creditLimit −1), `Accounts.InvalidInterestRate` (−1, 101); `lastDigits: "  "` → null; user B GET doesn't see user A's account and PUT/DELETE on it → 404 `Accounts.NotFound`.
- [ ] Run → FAIL. Implement domain (`Account.Create(userId, …)` / `Update(…)` returning `Result`), application, config, endpoints, migration `AddAccounts` (both tables, created here so Task 2 needs no migration — `AccountSnapshot` entity + configuration land in this task too, with no endpoints yet).
- [ ] Gates PASS → commit `feat: accounts (tài khoản) CRUD` → push.

### Task 2: BE — Snapshots + latest snapshot on accounts, resx

**Files:** Create `src/Domain/Accounts/AccountSnapshot.cs` (if not already from Task 1), `src/Application/Accounts/{SnapshotCommands.cs,GetAccountSnapshotsQuery.cs,GetAccountSnapshotsQueryHandler.cs,CreateAccountSnapshotCommandHandler.cs,UpdateAccountSnapshotCommandHandler.cs,DeleteAccountSnapshotCommandHandler.cs,Data/AccountSnapshotResponse.cs}`, `tests/Api.IntegrationTests/Accounts/AccountSnapshotsEndpointsTests.cs`; Modify `GetAccountsQueryHandler` (embed latest), `AccountEndpoints.cs`, DI, both resx files (ALL spec keys), `tests/Api.IntegrationTests/Resources/*` (assert new keys).

**Interfaces — Produces:**

```csharp
public sealed record CreateAccountSnapshotCommand(Guid AccountId, DateOnly Date, decimal Balance,
    decimal? StatementAmount = null, DateOnly? DueDate = null, decimal? InstallmentRemaining = null,
    bool StatementPaid = false, string? Note = null) : ICommand<Guid>;
public sealed record UpdateAccountSnapshotCommand(Guid Id, DateOnly Date, decimal Balance,
    decimal? StatementAmount = null, DateOnly? DueDate = null, decimal? InstallmentRemaining = null,
    bool StatementPaid = false, string? Note = null) : ICommand;
public sealed record DeleteAccountSnapshotCommand(Guid Id) : ICommand;
public sealed record GetAccountSnapshotsQuery(Guid AccountId) : IQuery<List<AccountSnapshotResponse>>;
```

Routes exactly as spec: `GET/POST /accounts/{id}/snapshots`, `PUT/DELETE /accounts/snapshots/{snapshotId}`. Latest = order by `Date` desc, then `CreatedAt` desc.

- [ ] Write failing tests: POST snapshot → `GET /accounts` embeds it as `latestSnapshot` with all fields; second snapshot with later date wins; **same date → later-created wins**; older-date snapshot added later does NOT win; history GET newest first; PUT changes every field (update-path) incl. `statementPaid: true`; DELETE removes; deleting the account cascades its snapshots (history GET → 404); validation: negative balance / statementAmount / installmentRemaining → `Accounts.NegativeAmount`, note 501 chars → `Accounts.NoteTooLong`, `note: "  "` → null; other user's account/snapshot → 404 (`Accounts.NotFound` / `Accounts.SnapshotNotFound`); resources endpoint returns every new vi key with the spec's value.
- [ ] Run → FAIL → implement → gates PASS → commit `feat: account balance snapshots + latest on accounts` and `feat: accounts resx keys (vi/en)` → push.

### Task 3: FE — types, API client, pure helpers

**Files:** Modify `src/api/types.ts`; Create `src/api/accountApi.ts`, `src/utils/accounts.ts`, `src/utils/accounts.test.ts`.

**Interfaces — Produces:**

```ts
export interface AccountSnapshotResponse { id: string; accountId: string; date: string;
  balance: MoneyResponse; statementAmount: MoneyResponse | null; dueDate: string | null;
  installmentRemaining: MoneyResponse | null; statementPaid: boolean; note: string | null }
export interface AccountResponse { id: string; name: string; type: AccountType;
  lastDigits: string | null; creditLimit: MoneyResponse | null; statementDay: number | null;
  dueDay: number | null; interestRatePercent: number | null; latestSnapshot: AccountSnapshotResponse | null }
export type AccountType = 'checking' | 'overdraft' | 'credit_card' | 'ewallet' | 'cash'
export interface AccountInput { name: string; type: AccountType; lastDigits: string | null;
  creditLimit: number | null; statementDay: number | null; dueDay: number | null; interestRatePercent: number | null }
export interface SnapshotInput { date: string; balance: number; statementAmount: number | null;
  dueDate: string | null; installmentRemaining: number | null; statementPaid: boolean; note: string | null }
// accountApi.ts
getAccounts(): Promise<AccountResponse[]>; createAccount(input: AccountInput): Promise<{ id: string }>
updateAccount(id: string, input: AccountInput): Promise<void>; deleteAccount(id: string): Promise<void>
getSnapshots(accountId: string): Promise<AccountSnapshotResponse[]>
createSnapshot(accountId: string, input: SnapshotInput): Promise<{ id: string }>
updateSnapshot(id: string, input: SnapshotInput): Promise<void>; deleteSnapshot(id: string): Promise<void>
// utils/accounts.ts
isDebtType(type: AccountType): boolean
cashTotal(accounts: AccountResponse[]): number
debtTotal(accounts: AccountResponse[]): number
availableCredit(accounts: AccountResponse[]): number
monthlyInterest(account: AccountResponse): number
upcomingDues(accounts: AccountResponse[], today: string): { account: AccountResponse; amount: number;
  dueDate: string; daysLeft: number; urgent: boolean }[]
```

- [ ] Failing vitest cases: cashTotal sums latest balances of checking/ewallet/cash only and skips accounts without snapshot; debtTotal sums overdraft + credit_card; availableCredit = Σ max(0, limit − owed), skips no-limit and no-snapshot debt accounts, **over-limit clamps to 0**; monthlyInterest = round(owed × rate / 100 / 12) for overdraft, 0 for other types or missing rate (e.g. 210_300_000 at 15% → 2_628_750); upcomingDues keeps credit cards with dueDate ≥ today, amount > 0, not paid, sorted by dueDate, daysLeft computed with dayjs, `urgent` true at 0…3 and false at 4; due yesterday / paid / amount 0 / non-card excluded.
- [ ] Run → FAIL → implement → `npm test && npm run build && npm run lint` → commit `feat: accounts api client and debt helpers` → push.

### Task 4: FE — Accounts page, route, menu

**Files:** Create `src/pages/AccountsPage.tsx`, `src/accounts/{AccountDialog.tsx,SnapshotDialog.tsx,SnapshotHistoryDialog.tsx}`, `src/pages/AccountsPage.test.tsx`; Modify `src/App.tsx` (route `accounts`), `src/layouts/AppLayout.tsx` (menu item `{ to: '/app/accounts', key: 'menu.accounts', icon: Landmark }` right after the savings item, in both nav lists if duplicated).

**Behavior (verbatim from spec "AccountsPage"):** stat tiles (cash green / debt red with `accounts.monthlyInterest` sub-line when > 0 / available credit); `accounts.upcoming` list with red styling when urgent, `accounts.dueToday` when daysLeft 0 else `t('accounts.left') N t('accounts.days')`, and an `accounts.markPaid` button calling `updateSnapshot(latest.id, {...latest fields, statementPaid: true})` then reload; account groups `accounts.groupMoney` / `groupOverdraft` / `groupCredit` (hide empty groups); each card: name + `•••1234` when lastDigits, current amount, for debt types with a limit a usage bar (owed/limit) + `accounts.available` amount, `accounts.lastUpdated <dd/MM/yyyy>` or `accounts.noSnapshot`, buttons update / history / edit / delete (AlertDialog `accounts.deleteConfirm`). AccountDialog shows limit/statementDay/dueDay/interestRate only when `isDebtType(type)` (and sends them null otherwise). SnapshotDialog: date default today; label `accounts.owed` for debt types else `accounts.balance`; debt types with a limit show an `accounts.available` input that, when typed, sets owed = max(0, limit − available); credit cards also show statementAmount / dueDate / installmentRemaining / statementPaid. Money inputs reuse the existing digit-only money input pattern from `TransactionFormModal` (amountDigits) — read it and mirror it.

- [ ] Failing page tests (mock `../api/accountApi`, `../api/resourceApi`; fixed `today` via `vi.setSystemTime`): tiles show the three totals; account with no snapshot shows `accounts.noSnapshot`; due list shows the urgent card and clicking `accounts.markPaid` calls `updateSnapshot` with `statementPaid: true`; AccountDialog hides debt fields for `checking` and shows them for `credit_card`; SnapshotDialog: typing available 121_507_335 for a 250_000_000-limit overdraft submits balance 128_492_665.
- [ ] Run → FAIL → implement → gates → commit `feat: accounts & debt page` → push.

### Task 5: FE — Dashboard due banner

**Files:** Modify `src/pages/DashboardPage.tsx`; Test in `src/pages/DashboardPage.test.tsx` (create if absent, mirroring other page tests' mocks).

- [ ] Failing test: with an urgent due from `getAccounts` mock, the dashboard renders a banner containing the card name, `accounts.dueIn`, the day count, `accounts.days` and the formatted amount, linking to `/app/accounts`; with no urgent dues, no banner; a `getAccounts` failure does not break the dashboard (banner simply absent, no toast spam).
- [ ] Run → FAIL → implement (fetch `getAccounts()` alongside existing loads; `upcomingDues(accounts, dayjs().format('YYYY-MM-DD')).filter(d => d.urgent)`) → gates → commit `feat: dashboard banner for credit cards due soon` → push.

### Task 6: Integration (controller, not a subagent)

- [ ] Whole-branch review of both repos; update `.claude/skills/dmoney-platform/SKILL.md` contract table (Accounts row) in the orchestrator and push.
- [ ] Back up the `dmoney` DB, rebuild docker (`docker compose build api web` in background, then `docker compose up -d api web`), confirm migration `AddAccounts` applied.
- [ ] Enter the owner's accounts + 2026-11-10 snapshots (spec "Data"; last 4 digits only) via SQL in one transaction; verify cash on hand 2_677_268 and total debt 128_492_665 + 24_625_403 + 90_678_586.
- [ ] Open PRs for be/web via the GitHub MCP tools (not `gh`).
