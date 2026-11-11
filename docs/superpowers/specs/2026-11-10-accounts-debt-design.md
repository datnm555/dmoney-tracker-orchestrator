# Accounts & Debt (Tài khoản & Nợ) — Design

## Goal

One page that answers: how much real money do I have, how much do I owe
(overdraft + credit cards), what is due soon, and what does the overdraft cost
per month. Balances are **entered by hand from the bank app** (snapshot per
statement / whenever the user checks), not computed from transactions — so
the page always matches the bank and does not depend on complete bookkeeping.

Out of scope (later rounds): net worth incl. gold/savings, balance
reconciliation from transactions, recurring transactions, budgets, duplicate
warnings. Transactions are NOT linked to accounts in this round.

## Concepts

- **Account (Tài khoản)** — per-user, not plan-scoped (like banks / gold).
  Type decides how its balance is read:
  - money types: `checking` (Thanh toán), `ewallet` (Ví điện tử), `cash` (Tiền mặt) → balance = money held (≥ 0).
  - debt types: `overdraft` (Thấu chi), `credit_card` (Thẻ tín dụng) → balance = amount owed (≥ 0).
- **Snapshot (Cập nhật số dư)** — a dated reading of one account. The newest
  snapshot (by `Date`, then `CreatedAt`) is the account's current state.

## Backend (`dmoney-tracker-be`)

### Domain

`Domain/Accounts/Account.cs` (AuditedEntity):

| Field | Type | Rules |
|---|---|---|
| UserId | Guid | owner |
| Name | string | required, trimmed, ≤ 100 |
| Type | string | one of `AccountTypes.All` (`checking`, `overdraft`, `credit_card`, `ewallet`, `cash`), max length 20 |
| LastDigits | string? | empty → null; exactly 4 digits when set |
| CreditLimit | decimal? | ≥ 0; only meaningful for debt types (stored as given) |
| StatementDay | int? | 1–31 |
| DueDay | int? | 1–31 |
| InterestRatePercent | decimal? | annual %, 0–100 |

`Domain/Accounts/AccountSnapshot.cs` (AuditedEntity):

| Field | Type | Rules |
|---|---|---|
| AccountId | Guid | FK → accounts, cascade delete |
| Date | DateOnly | required |
| Balance | decimal | ≥ 0 (money held, or amount owed for debt types) |
| StatementAmount | decimal? | ≥ 0 — credit card "phải trả kỳ này" |
| DueDate | DateOnly? | credit card payment due date |
| InstallmentRemaining | decimal? | ≥ 0 — credit card trả góp còn lại |
| StatementPaid | bool | default false |
| Note | string? | empty → null, ≤ 500 |

Errors (`AccountErrors`): `Accounts.NotFound` (404), `Accounts.NameRequired`,
`Accounts.NameTooLong`, `Accounts.InvalidType`, `Accounts.InvalidLastDigits`,
`Accounts.InvalidDay`, `Accounts.NegativeAmount`, `Accounts.InvalidInterestRate`,
`Accounts.SnapshotNotFound` (404), `Accounts.NoteTooLong`. Every code gets a
vi/en resx message.

Migration `AddAccounts` (tables `accounts`, `account_snapshots`; money columns
`numeric(18,2)`, rate `numeric(5,2)`).

### API (all `RequireAuthorization`, user-scoped; another user's ids → 404)

| Method | Route | Body / result |
|---|---|---|
| GET | `/accounts` | `AccountResponse[]` ordered by type group (money types first, then overdraft, then credit_card), then name |
| POST | `/accounts` | `{ name, type, lastDigits?, creditLimit?, statementDay?, dueDay?, interestRatePercent? }` → 201 `{ id }` |
| PUT | `/accounts/{id}` | same body (explicit request record) → 204 |
| DELETE | `/accounts/{id}` | → 204 (snapshots cascade) |
| GET | `/accounts/{id}/snapshots` | `AccountSnapshotResponse[]` newest first |
| POST | `/accounts/{id}/snapshots` | `{ date, balance, statementAmount?, dueDate?, installmentRemaining?, statementPaid?, note? }` → 201 `{ id }` |
| PUT | `/accounts/snapshots/{snapshotId}` | same body → 204 |
| DELETE | `/accounts/snapshots/{snapshotId}` | → 204 |

```csharp
public sealed record AccountResponse(
    Guid Id, string Name, string Type, string? LastDigits,
    MoneyResponse? CreditLimit, int? StatementDay, int? DueDay,
    decimal? InterestRatePercent, AccountSnapshotResponse? LatestSnapshot);

public sealed record AccountSnapshotResponse(
    Guid Id, Guid AccountId, DateOnly Date, MoneyResponse Balance,
    MoneyResponse? StatementAmount, DateOnly? DueDate,
    MoneyResponse? InstallmentRemaining, bool StatementPaid, string? Note);
```

No summary endpoint: totals are derived on the client from `GET /accounts`.

## Frontend (`dmoney-tracker-web`)

- `src/api/types.ts` mirrors; `src/api/accountApi.ts`; pure helpers in
  `src/utils/accounts.ts` (unit-tested):
  - `isDebtType(type)`, `cashTotal(accounts)` (latest balance of money types),
    `debtTotal(accounts)` (latest balance of debt types),
    `availableCredit(accounts)` (Σ max(0, limit − owed) over debt types with a limit),
    `monthlyInterest(account)` (overdraft only: owed × rate / 100 / 12, rounded),
    `upcomingDues(accounts, today)` → credit cards whose latest snapshot has
    a `dueDate`, `statementAmount > 0`, `!statementPaid`, sorted by
    due date, with `daysLeft` (negative = overdue); `urgent = daysLeft ≤ 3`
    (so overdue unpaid statements stay listed and urgent, labelled `accounts.overdue`).
- Route `/app/accounts` ("Tài khoản & Nợ") + sidebar entry next to Tiết kiệm.
- `AccountsPage`:
  - 3 stat tiles: **Tiền đang có** (green), **Tổng nợ** (red), **Hạn mức còn dùng được**; plus "Lãi thấu chi ước tính / tháng" under the debt tile when > 0.
  - **Sắp đến hạn** list (card name •••last4, amount, due date, days left; red when urgent) with a **Đã trả** button → PUT latest snapshot with `statementPaid: true`.
  - Account cards grouped: Tiền / Thấu chi / Thẻ tín dụng. Each shows name •••last4, current balance (owed for debt types), for debt types a usage bar (owed / limit) and available amount, last updated date, and actions: **Cập nhật số dư**, history, edit, delete.
  - **Account dialog**: name, type, last 4 digits, and for debt types limit, statement day, due day, interest rate.
  - **Snapshot dialog**: date (default today); a new reading on a credit card carries over statement amount / due date / installment / paid from the latest snapshot, balance (label "Số dư" or "Dư nợ" by type). Debt types with a limit get an optional **"Khả dụng"** helper that fills Dư nợ = limit − khả dụng. Credit cards also show statement amount, due date, installment remaining, paid checkbox. Note.
  - **History** dialog: snapshots newest first with edit/delete.
- Dashboard: a warning banner when `upcomingDues` has an urgent item ("Thẻ X đến hạn sau N ngày: Y ₫", composed per the i18n note), linking to `/app/accounts`.

## i18n (resx, vi / en — added to both files, same order)

The i18n layer has no placeholders: the web composes phrases, e.g. "còn 3 ngày" = `t('accounts.left') 3 t('accounts.days')`, banner = `<card> t('accounts.dueIn') 3 t('accounts.days'): <amount>`, "Cập nhật 10/11/2026" = `t('accounts.lastUpdated') <date>`.

`menu.accounts` Tài khoản & Nợ / Accounts & Debt ·
`accounts.title` Tài khoản & Nợ / Accounts & Debt ·
`accounts.hint` Số dư nhập tay theo app ngân hàng — không tính từ giao dịch. / Balances are entered from your bank app — not computed from transactions. ·
`accounts.cashTotal` Tiền đang có / Cash on hand ·
`accounts.debtTotal` Tổng nợ / Total debt ·
`accounts.availableCredit` Hạn mức còn dùng được / Available credit ·
`accounts.monthlyInterest` Lãi thấu chi ước tính / tháng / Est. overdraft interest / month ·
`accounts.upcoming` Sắp đến hạn / Due soon ·
`accounts.left` còn / in ·
`accounts.days` ngày / days ·
`accounts.dueToday` hôm nay / today ·
`accounts.markPaid` Đã trả / Mark paid ·
`accounts.groupMoney` Tiền / Money ·
`accounts.groupOverdraft` Thấu chi / Overdraft ·
`accounts.groupCredit` Thẻ tín dụng / Credit cards ·
`accounts.add` Thêm tài khoản / Add account ·
`accounts.edit` Sửa tài khoản / Edit account ·
`accounts.deleteConfirm` Xoá tài khoản này và toàn bộ lịch sử số dư? / Delete this account and its balance history? ·
`accounts.name` Tên / Name ·
`accounts.type` Loại / Type ·
`accounts.type.checking` Thanh toán / Checking ·
`accounts.type.overdraft` Thấu chi / Overdraft ·
`accounts.type.credit_card` Thẻ tín dụng / Credit card ·
`accounts.type.ewallet` Ví điện tử / E-wallet ·
`accounts.type.cash` Tiền mặt / Cash ·
`accounts.lastDigits` 4 số cuối / Last 4 digits ·
`accounts.creditLimit` Hạn mức / Credit limit ·
`accounts.statementDay` Ngày sao kê / Statement day ·
`accounts.dueDay` Ngày đến hạn / Due day ·
`accounts.interestRate` Lãi suất (%/năm) / Interest rate (%/yr) ·
`accounts.updateBalance` Cập nhật số dư / Update balance ·
`accounts.history` Lịch sử số dư / Balance history ·
`accounts.date` Ngày / Date ·
`accounts.balance` Số dư / Balance ·
`accounts.owed` Dư nợ / Amount owed ·
`accounts.available` Khả dụng / Available ·
`accounts.statementAmount` Phải trả kỳ này / Statement amount ·
`accounts.dueDate` Hạn thanh toán / Due date ·
`accounts.installmentRemaining` Trả góp còn lại / Installments remaining ·
`accounts.statementPaid` Đã thanh toán kỳ này / Statement paid ·
`accounts.note` Ghi chú / Note ·
`accounts.lastUpdated` Cập nhật / Updated ·
`accounts.empty` Chưa có tài khoản nào / No accounts yet ·
`accounts.noSnapshot` Chưa cập nhật số dư / No balance yet ·
`accounts.dueIn` đến hạn sau / due in ·
`accounts.overdue` quá hạn / overdue
— plus one message per `Accounts.*` error code.

## Testing

- BE integration: CRUD + validation for accounts and snapshots (each error code),
  user isolation (other user's account/snapshot → 404), cascade delete,
  `latestSnapshot` picks newest by date then createdAt, PUT request records
  thread every field (update-path test).
- FE: `utils/accounts.ts` unit tests (totals, available credit, interest,
  upcoming dues incl. paid/past/zero filtering and urgency boundary at 3 days);
  page tests (tiles, due list + Đã trả call, Khả dụng helper fills Dư nợ,
  account dialog shows debt fields only for debt types); dashboard banner.

## Data (after deploy, entered for the owner)

Accounts: VPBank lương, VPBank thấu chi (limit 250tr, 15%/yr), Techcombank 1,
Techcombank 2, VietinBank, Momo, thẻ VietinBank (5tr), thẻ VPBank (50tr, due
11/11), thẻ Techcombank (200tr, due 13/11), with snapshots dated 2026-11-10
from the figures the owner gave. Full account numbers are never stored — last
4 digits only.
