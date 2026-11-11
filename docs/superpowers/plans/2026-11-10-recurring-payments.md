# Recurring Payments (Lịch thanh toán) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A monthly "Lịch thanh toán" checklist of recurring payments (plus credit-card statements) where the owner records each payment through a pre-filled transaction form.

**Architecture:** Two new per-user aggregates in the backend (`RecurringPayment` template, `RecurringPaymentRecord` per item per month, optional link to the created transaction) with CRUD, a month schedule endpoint and record endpoints. The web gets pure schedule helpers, a shared `toTransactionPayload`, a `prefill` prop on `TransactionFormModal`, a new page and a dashboard banner extension.

**Tech Stack:** unchanged (.NET 10 Clean Architecture + custom CQRS + EF Core/Npgsql; React 19 + Tailwind v4 + shadcn/ui + vitest).

**Spec:** `docs/superpowers/specs/2026-11-10-recurring-payments-design.md` (orchestrator repo) — field rules, routes, response records, error codes and resx keys/values there are verbatim requirements.

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`, both on a new branch `feature/recurring-payments` cut from the current `feature/accounts` HEAD (accounts work is not merged yet; its PRs will absorb). Never commit product code in the orchestrator repo.
- Template for every layer: the Accounts feature on the same branch (BE `src/Domain/Accounts`, `src/Application/Accounts`, `src/Web.Api/Endpoints/Accounts/AccountEndpoints.cs`, `tests/Api.IntegrationTests/Accounts/*`; FE `src/api/accountApi.ts`, `src/utils/accounts.ts`, `src/pages/AccountsPage.tsx`, `src/accounts/*`).
- Handlers `internal sealed`, explicit DI; DbSets on `IApplicationDbContext` + `ApplicationDbContext`. Every PUT uses an explicit request record threading EVERY field, with an update-path integration test.
- Migration `AddRecurringPayments` via `dotnet dotnet-ef migrations add AddRecurringPayments --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations` (scaffold untouched); unique index (RecurringPaymentId, Period); record FK to transactions ON DELETE SET NULL; record FK to item cascade.
- Payment method codes: `Domain/Transactions/PaymentMethods.cs` (`transfer`, `cash`, `card`) — validate with `PaymentMethods.IsValid`.
- Money in responses: `MoneyResponse` + `Money.DefaultCurrency`. Period strings `YYYY-MM` (validate with the same parsing the month endpoints use — `GetTransactionsByMonthQueryHandler`).
- i18n: NO placeholders; resx keys in both files, same order, asserted in the resources test.
- Gates — BE: `dotnet build DMoney.slnx` (0 warnings) && `dotnet test DMoney.slnx`; FE: `npm test && npm run build && npm run lint` (lint stays at 9 warnings). Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push after each green task; never force-push; no PRs from tasks.

## Review Focus

- DayOfMonth 31 in February/November → due date clamps to the month's last day (BE schedule test, Task 2).
- Variable item with amount 0 → shows `recurring.enterAmount`, contributes 0 to totals until paid; once paid contributes the record amount (FE util + page test, Tasks 3/4).
- "Ghi nhận" where the owner edits the amount → the record stores the edited amount and the returned transaction id; if `createTransaction` fails no record is created; if record creation fails after the transaction was created the user sees an error toast and the transaction stays (FE page test, Task 4).
- Recording the same item twice in one month → 409 `RecurringPayments.AlreadyPaid`, surfaced as a toast (BE Task 2, FE Task 4).
- Deleting the linked transaction → record survives with `transactionId` null and still counts as paid (BE Task 2).

---

### Task 1: BE — RecurringPayment CRUD (+ record entity, migration)

**Files:** Create `src/Domain/RecurringPayments/{RecurringPayment.cs,RecurringPaymentRecord.cs,RecurringPaymentConstants.cs,RecurringPaymentErrors.cs}`, `src/Application/RecurringPayments/{RecurringPaymentCommands.cs,GetRecurringPaymentsQuery.cs,GetRecurringPaymentsQueryHandler.cs,CreateRecurringPaymentCommandHandler.cs,UpdateRecurringPaymentCommandHandler.cs,DeleteRecurringPaymentCommandHandler.cs,Data/RecurringPaymentResponse.cs,Data/RecurringPaymentRecordResponse.cs}`, `src/Infrastructure/RecurringPayments/{RecurringPaymentConfiguration.cs,RecurringPaymentRecordConfiguration.cs}`, `src/Web.Api/Endpoints/RecurringPayments/RecurringPaymentEndpoints.cs`, `tests/Api.IntegrationTests/RecurringPayments/RecurringPaymentsEndpointsTests.cs`; Modify DI, DbContext interface/impl, both resx (all `RecurringPayments.*` error messages).

**Interfaces — Produces:**

```csharp
public sealed record CreateRecurringPaymentCommand(string Name, Guid? CategoryId, Guid? SubCategoryId,
    decimal Amount, bool IsVariable, int DayOfMonth, string? PaymentMethod = null, string? Bank = null,
    string? Note = null, bool IsActive = true) : ICommand<Guid>;
public sealed record UpdateRecurringPaymentCommand(Guid Id, string Name, Guid? CategoryId, Guid? SubCategoryId,
    decimal Amount, bool IsVariable, int DayOfMonth, string? PaymentMethod = null, string? Bank = null,
    string? Note = null, bool IsActive = true) : ICommand;
public sealed record DeleteRecurringPaymentCommand(Guid Id) : ICommand;
public sealed record GetRecurringPaymentsQuery : IQuery<List<RecurringPaymentResponse>>;
// RecurringPaymentResponse / RecurringPaymentRecordResponse exactly as in the spec.
```

- [ ] Failing integration tests: create → GET returns every field; PUT changes every field then clears optionals (update path); DELETE; ordering (active first, then DayOfMonth, then Name); validation → `NameRequired`, `NameTooLong` (101), `NegativeAmount` (−1), `InvalidDay` (0, 32), `InvalidCategory` (random Guid), `InvalidSubCategory` (sub of another category; sub without category), `InvalidPaymentMethod` ("bitcoin"), `BankTooLong` (101), `NoteTooLong` (501); blank bank/note → null; other user → 404 on PUT/DELETE and absent from GET.
- [ ] Implement (record entity + configuration in this task so the single migration creates both tables; no record endpoints yet) → gates → commit `feat: recurring payments (khoản định kỳ) CRUD` → push.

### Task 2: BE — schedule + records, UI resx

**Files:** Create `src/Application/RecurringPayments/{GetRecurringScheduleQuery.cs,GetRecurringScheduleQueryHandler.cs,RecordCommands.cs,GetRecurringPaymentRecordsQuery.cs,GetRecurringPaymentRecordsQueryHandler.cs,CreateRecurringPaymentRecordCommandHandler.cs,DeleteRecurringPaymentRecordCommandHandler.cs,Data/RecurringScheduleItemResponse.cs}`, `tests/Api.IntegrationTests/RecurringPayments/RecurringScheduleEndpointsTests.cs`; Modify endpoints, DI, both resx (ALL spec UI keys), resources test.

**Interfaces — Produces:**

```csharp
public sealed record GetRecurringScheduleQuery(string Month) : IQuery<List<RecurringScheduleItemResponse>>;
public sealed record CreateRecurringPaymentRecordCommand(Guid RecurringPaymentId, string Period, decimal Amount,
    DateOnly PaidDate, Guid? TransactionId = null) : ICommand<Guid>;
public sealed record DeleteRecurringPaymentRecordCommand(Guid Id) : ICommand;
public sealed record GetRecurringPaymentRecordsQuery(Guid RecurringPaymentId) : IQuery<List<RecurringPaymentRecordResponse>>;
```

Due date = `new DateOnly(y, m, Math.Min(DayOfMonth, DateTime.DaysInMonth(y, m)))`.

- [ ] Failing tests: schedule for `2026-11` lists active items only with due dates, sorted by due date then name; DayOfMonth 31 → 2026-11-30 and 2026-02-28; record attached only for its own period; bad month → 400 `InvalidPeriod`; POST record → 201 and appears in schedule + history (newest period first); same period again → 409 `AlreadyPaid`; transactionId of another user / nonexistent → 400 `InvalidTransaction`; negative amount → `NegativeAmount`; DELETE record → schedule shows unpaid and the transaction still exists; DELETE the linked transaction (existing endpoint) → record remains with `transactionId` null; deleting the item cascades records; other user → 404 on every record route; resources test asserts every new vi + en key with the spec value.
- [ ] Implement → gates → commit `feat: recurring schedule and payment records` + `feat: recurring payments resx keys (vi/en)` → push.

### Task 3: FE — types, API, helpers, payload builder, form prefill

**Files:** Modify `src/api/types.ts`, `src/components/TransactionFormModal.tsx`, `src/pages/TransactionsPage.tsx`; Create `src/api/recurringPaymentApi.ts`, `src/utils/recurring.ts`, `src/utils/recurring.test.ts`, `src/utils/transactionPayload.ts`, `src/utils/transactionPayload.test.ts`; extend `src/components/TransactionFormModal.test.tsx`.

**Interfaces — Produces:**

```ts
export interface RecurringPaymentResponse { id: string; name: string; categoryId: string | null;
  subCategoryId: string | null; amount: MoneyResponse; isVariable: boolean; dayOfMonth: number;
  paymentMethod: string | null; bank: string | null; note: string | null; isActive: boolean }
export interface RecurringPaymentRecordResponse { id: string; recurringPaymentId: string; period: string;
  amount: MoneyResponse; paidDate: string; transactionId: string | null }
export interface RecurringScheduleItemResponse { item: RecurringPaymentResponse; dueDate: string;
  record: RecurringPaymentRecordResponse | null }
export interface RecurringPaymentInput { name: string; categoryId: string | null; subCategoryId: string | null;
  amount: number; isVariable: boolean; dayOfMonth: number; paymentMethod: string | null; bank: string | null;
  note: string | null; isActive: boolean }
// recurringPaymentApi.ts
getRecurringPayments(): Promise<RecurringPaymentResponse[]>
createRecurringPayment(input: RecurringPaymentInput): Promise<{ id: string }>
updateRecurringPayment(id: string, input: RecurringPaymentInput): Promise<void>
deleteRecurringPayment(id: string): Promise<void>
getSchedule(month: string): Promise<RecurringScheduleItemResponse[]>
getRecords(id: string): Promise<RecurringPaymentRecordResponse[]>
createRecord(id: string, input: { period: string; amount: number; paidDate: string; transactionId: string | null }): Promise<{ id: string }>
deleteRecord(recordId: string): Promise<void>
// utils/recurring.ts
type ScheduleStatus = 'paid' | 'overdue' | 'dueSoon' | 'upcoming'
scheduleStatus(row: RecurringScheduleItemResponse, today: string): { status: ScheduleStatus; daysLeft: number }
cardDuesInMonth(accounts: AccountResponse[], month: string): { account: AccountResponse; amount: number; dueDate: string; paid: boolean }[]
scheduleTotals(rows: RecurringScheduleItemResponse[], cards: ReturnType<typeof cardDuesInMonth>): { total: number; paid: number; remaining: number }
// utils/transactionPayload.ts
toTransactionPayload(values: TransactionFormValues, planId: string): TransactionPayload
// TransactionFormModal Props gains: prefill?: Partial<TransactionFormValues>
```

- [ ] Failing tests: scheduleStatus — paid when record; daysLeft from `dayjs(dueDate).diff(dayjs(today),'day')`; dueSoon at 0 and 3, upcoming at 4, overdue at −1 (unpaid). scheduleTotals — paid rows count record amount; unpaid fixed rows count item amount; unpaid variable amount-0 rows count 0; cards add statement amount to total and to paid when paid. cardDuesInMonth — includes paid and unpaid cards with dueDate in month and amount > 0; excludes other months, no snapshot, non-card. toTransactionPayload — maps a full TransactionFormValues fixture exactly like the current TransactionsPage inline mapping (in → creditAmount, out → debitAmount; `planId: values.planId ?? planId`). TransactionFormModal — with `prefill` in create mode the content/amount/category/sub/paymentMethod/bank fields show the prefilled values and submit returns them; edit mode ignores prefill; without prefill behaviour unchanged.
- [ ] Implement; TransactionsPage uses `toTransactionPayload` (its existing tests stay green) → gates → commit `feat: recurring api, schedule helpers, shared payload, form prefill` → push.

### Task 4: FE — Lịch thanh toán page, manage dialog, route, menu

**Files:** Create `src/pages/RecurringPage.tsx`, `src/pages/RecurringPage.test.tsx`, `src/recurring/{RecurringItemDialog.tsx,RecurringManageDialog.tsx,MarkPaidDialog.tsx,RecordHistoryDialog.tsx}`; Modify `src/App.tsx` (route `recurring`), `src/layouts/AppLayout.tsx` (`{ to: '/app/recurring', key: 'menu.recurring', icon: CalendarClock }` right after the accounts item).

**Behavior (verbatim from spec "RecurringPage"):** month picker (default current month, `YYYY-MM`); tiles total/paid (green)/remaining (red) from `scheduleTotals`; checklist rows sorted by due date mixing item rows and card rows (`cardDuesInMonth` from `getAccounts()`); item row shows category icon (existing `CategoryIcon`), name, due date `DD/MM`, amount (`≈` prefix when variable+unpaid; `recurring.enterAmount` when variable, amount 0, unpaid), status chip (paid → `recurring.paid` + paid amount + `recurring.paidOn` date; overdue → `accounts.overdue` N `accounts.days` red; dueSoon → `accounts.dueToday` at 0 else `accounts.left` N `accounts.days` red; upcoming → `recurring.statusUpcoming`), actions `recurring.record`, `recurring.markPaid`, `recurring.undo` (when paid), `recurring.history`; card rows show name •••last4, `recurring.cardRow`, statement amount, status from `paid`, and `accounts.markPaid` → same `updateSnapshot` call as AccountsPage. **Ghi nhận** opens `TransactionFormModal` with `prefill = { content: item.name, type: 'out', amount: item.amount.amount || undefined, categoryId, subCategoryId, paymentMethod, bank, date: today }`; on submit `createTransaction(toTransactionPayload(values, selectedPlanId))` → `createRecord(item.id, { period: month, amount: values.amount, paidDate: values.date, transactionId: id })` → reload; errors toast via `getApiErrorMessage`. MarkPaidDialog: amount (MoneyInput from `src/accounts/MoneyInput.tsx`) + date → `createRecord(..., transactionId: null)`. Manage dialog: list of all items (inactive greyed) with add/edit/delete (AlertDialog `recurring.deleteConfirm`); item dialog fields per spec (category + sub-category selects using `useCategoryDisplay` options and `getSubCategories()` filtered by category; bank chips from `useBanks()`; payment method select using `src/utils/paymentMethods.ts`).

- [ ] Failing page tests (mock recurringPaymentApi, accountApi, transactionApi, resourceApi, plans context; `vi.useFakeTimers({ toFake: ['Date'] })` + `vi.setSystemTime`): tiles and statuses for a fixture month (paid, overdue, dueSoon, upcoming, variable-0 shows `recurring.enterAmount`, card row); Ghi nhận with edited amount → `createTransaction` then `createRecord` with that amount and the returned id; `createTransaction` rejection → no `createRecord`; `createRecord` 409 → toast, list reloaded; mark paid; undo → `deleteRecord`; card row `accounts.markPaid` → `updateSnapshot` with `statementPaid: true`; manage dialog create sends the full `RecurringPaymentInput`.
- [ ] Implement → gates → commit `feat: lịch thanh toán page` → push.

### Task 5: FE — Dashboard banner includes recurring dues

**Files:** Modify `src/pages/DashboardPage.tsx`, `src/pages/DashboardPage.test.tsx`.

- [ ] Failing tests: with `getSchedule(currentMonth)` returning an unpaid item due in 2 days and another overdue by 1, the banner lists both (`<name> recurring.dueIn 2 accounts.days: <amount>`; `<name> accounts.overdue 1 accounts.days`), linking to `/app/recurring`; paid or upcoming (4+ days) items not listed; variable amount-0 items listed without an amount (`recurring.enterAmount`); `getSchedule` failure → no banner lines from it, card banner unaffected, no toast.
- [ ] Implement (independent fetch, same pattern as the accounts fetch) → gates → commit `feat: dashboard banner for recurring payments due` → push.

### Task 6: Integration (controller)

- [ ] Whole-branch review of both repos; platform skill contract row (local, orchestrator commits pending owner).
- [ ] Back up DB, rebuild docker, confirm migration `AddRecurringPayments`, seed the 7 items from spec "Data" for the owner, verify `GET /recurring-payments/schedule?month=2026-11` count via SQL equivalence.
- [ ] Open PRs (or report if PR creation is blocked).
