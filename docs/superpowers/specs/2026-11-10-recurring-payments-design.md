# Recurring payments (Lịch thanh toán) — Design

## Goal

One monthly checklist of everything the owner must pay — parking (ô tô +
xe máy ở hầm, xe máy ở cơ quan), điện, nước, phí dịch vụ chung cư,
subscriptions (Claude Code, YouTube, Google Drive) — plus the credit-card
statements already tracked on "Tài khoản & Nợ". Each month the owner sees
what is due, what is paid, what is overdue, and records a payment with one
click that opens a pre-filled transaction form (amount confirmed by the
owner, so variable bills are never recorded wrong).

Decisions (owner): approach A (templates + monthly checklist + "Ghi nhận"),
no automatic transaction creation; reminder window **3 days** (same as
cards). Variable items: điện, nước, phí dịch vụ (CĐT fee still unsettled),
USD subscriptions (FX). Out of scope: budgets, auto-creation, notifications
outside the app, multi-month overdue carry-over (an unpaid item is shown in
the month it belongs to).

## Backend (`dmoney-tracker-be`)

### Domain

`Domain/RecurringPayments/RecurringPayment.cs` (per-user AuditedEntity):

| Field | Type | Rules |
|---|---|---|
| UserId | Guid | owner |
| Name | string | required, trimmed, ≤ 100 |
| CategoryId | Guid? | must exist when set |
| SubCategoryId | Guid? | must exist and belong to CategoryId when set (requires CategoryId) |
| Amount | decimal | ≥ 0 — fixed amount, or the estimate when `IsVariable`; `IsVariable` with Amount 0 = "no estimate, owner enters it" |
| IsVariable | bool | default false |
| DayOfMonth | int | 1–31; in short months the due date clamps to the last day |
| PaymentMethod | string? | a `PaymentMethods` code when set |
| Bank | string? | free text, empty → null, ≤ 100 (same as transaction `bank`) |
| Note | string? | empty → null, ≤ 500 |
| IsActive | bool | default true; inactive items are hidden from the schedule |

`Domain/RecurringPayments/RecurringPaymentRecord.cs` (AuditedEntity) — one
payment of one item for one month:

| Field | Type | Rules |
|---|---|---|
| RecurringPaymentId | Guid | FK, cascade delete |
| Period | string | `YYYY-MM`; unique per (RecurringPaymentId, Period) |
| Amount | decimal | ≥ 0 — the amount actually paid |
| PaidDate | DateOnly | required |
| TransactionId | Guid? | FK → transactions, ON DELETE SET NULL; must belong to the user |

Errors (`RecurringPaymentErrors`, all with vi/en resx messages):
`RecurringPayments.NotFound` (404), `RecurringPayments.NameRequired`,
`RecurringPayments.NameTooLong`, `RecurringPayments.NegativeAmount`,
`RecurringPayments.InvalidDay`, `RecurringPayments.InvalidCategory`,
`RecurringPayments.InvalidSubCategory`, `RecurringPayments.InvalidPaymentMethod`,
`RecurringPayments.BankTooLong`, `RecurringPayments.NoteTooLong`,
`RecurringPayments.InvalidPeriod`, `RecurringPayments.AlreadyPaid` (409),
`RecurringPayments.RecordNotFound` (404), `RecurringPayments.InvalidTransaction`.

Migration `AddRecurringPayments` (tables `recurring_payments`,
`recurring_payment_records`; money `numeric(18,2)`; unique index on
(RecurringPaymentId, Period)).

### API (all `RequireAuthorization`, user-scoped; other user's ids → 404)

| Method | Route | Body / result |
|---|---|---|
| GET | `/recurring-payments` | `RecurringPaymentResponse[]` (active first, then by DayOfMonth, then Name) |
| POST | `/recurring-payments` | `{ name, categoryId?, subCategoryId?, amount, isVariable, dayOfMonth, paymentMethod?, bank?, note?, isActive }` → 201 `{ id }` |
| PUT | `/recurring-payments/{id}` | same body (explicit request record) → 204 |
| DELETE | `/recurring-payments/{id}` | → 204 (records cascade; linked transactions untouched) |
| GET | `/recurring-payments/schedule?month=YYYY-MM` | `RecurringScheduleItemResponse[]` for ACTIVE items, sorted by due date then name |
| GET | `/recurring-payments/{id}/records` | `RecurringPaymentRecordResponse[]` newest period first |
| POST | `/recurring-payments/{id}/records` | `{ period, amount, paidDate, transactionId? }` → 201 `{ id }`; existing record for that period → 409 `AlreadyPaid` |
| DELETE | `/recurring-payments/records/{recordId}` | → 204 (undo; the linked transaction is NOT deleted) |

```csharp
public sealed record RecurringPaymentResponse(
    Guid Id, string Name, Guid? CategoryId, Guid? SubCategoryId, MoneyResponse Amount,
    bool IsVariable, int DayOfMonth, string? PaymentMethod, string? Bank, string? Note, bool IsActive);

public sealed record RecurringPaymentRecordResponse(
    Guid Id, Guid RecurringPaymentId, string Period, MoneyResponse Amount,
    DateOnly PaidDate, Guid? TransactionId);

public sealed record RecurringScheduleItemResponse(
    RecurringPaymentResponse Item, DateOnly DueDate, RecurringPaymentRecordResponse? Record);
```

## Frontend (`dmoney-tracker-web`)

- `src/api/types.ts` mirrors; `src/api/recurringPaymentApi.ts`.
- Pure helpers `src/utils/recurring.ts` (unit-tested):
  - `scheduleStatus(row, today)` → `'paid' | 'overdue' | 'dueSoon' | 'upcoming'` with `daysLeft` (dueSoon = 0…3 days, overdue = negative and unpaid).
  - `scheduleTotals(rows, cardRows)` → `{ total, paid, remaining }` (row amount = record amount when paid, else item amount — a variable item with amount 0 contributes 0 until paid; card rows use statement amount).
  - `cardDuesInMonth(accounts, month)` → credit cards whose latest snapshot has `dueDate` in that month and `statementAmount > 0` (paid or not).
- Shared payload builder: extract the `TransactionFormValues → payload` mapping from `TransactionsPage.handleSubmit` into `src/utils/transactionPayload.ts` (`toTransactionPayload(values, planId)`), used by both pages (no behaviour change for TransactionsPage).
- `TransactionFormModal` gains optional `prefill?: Partial<TransactionFormValues>` applied in create mode only (content, amount, type, categoryId, subCategoryId, paymentMethod, bank, date, note). Existing defaults (default bank, default beneficiary) apply only to fields the prefill leaves undefined.
- Route `/app/recurring` "Lịch thanh toán" + menu item (icon `CalendarClock`) right after "Tài khoản & Nợ".
- `RecurringPage`:
  - Month picker (default current month).
  - Tiles: **Phải trả tháng này** / **Đã trả** (green) / **Còn lại** (red).
  - Checklist sorted by due date: item rows (category icon, name, due date, amount — "≈" prefix when variable and unpaid, or `recurring.enterAmount` when variable with amount 0 and unpaid; status chip: Đã trả + paid amount/date, Quá hạn N ngày (red), Còn N ngày (red when ≤ 3), Hôm nay; actions: **Ghi nhận**, **Đánh dấu đã trả** (amount + date only, no transaction), **Hoàn tác** when paid, **Lịch sử** (records by month)) and read-only card rows from `cardDuesInMonth` (name •••last4, statement amount, due date, status from `statementPaid`; action **Đã trả** = same PUT as the Accounts page).
  - **Ghi nhận**: opens `TransactionFormModal` with `prefill` from the item (content = name, type out, amount, category/sub, paymentMethod, bank, date today); on submit `createTransaction(toTransactionPayload(values, selectedPlanId))` then `POST …/records { period: month, amount: values.amount, paidDate: values.date, transactionId }`; reload.
  - **Manage items** dialog (list + create/edit/delete with confirm): name, category + sub-category selects (existing contexts), amount, "Số tiền thay đổi hàng tháng" checkbox, day of month, payment method, bank chips (banks catalog), note, active.
- Dashboard: the existing due banner also lists unpaid recurring items of the current month that are overdue or due within 3 days (`<name> t('recurring.dueIn') N t('accounts.days'): <amount>` / `t('accounts.dueTodayFull')` / `t('accounts.overdue') N t('accounts.days')`), linking to `/app/recurring`. Failure of either fetch never breaks the dashboard.

## i18n (vi / en, both files, same order; no placeholders — compose in the web)

`menu.recurring` Lịch thanh toán / Payment schedule ·
`recurring.title` Lịch thanh toán / Payment schedule ·
`recurring.hint` Các khoản trả hàng tháng — bấm Ghi nhận để tạo giao dịch đã điền sẵn. / Monthly payments — press Record to create a pre-filled transaction. ·
`recurring.total` Phải trả tháng này / Due this month ·
`recurring.paid` Đã trả / Paid ·
`recurring.remaining` Còn lại / Remaining ·
`recurring.record` Ghi nhận / Record ·
`recurring.markPaid` Đánh dấu đã trả / Mark paid ·
`recurring.undo` Hoàn tác / Undo ·
`recurring.history` Lịch sử / History ·
`recurring.manage` Quản lý khoản định kỳ / Manage recurring items ·
`recurring.add` Thêm khoản / Add item ·
`recurring.edit` Sửa khoản / Edit item ·
`recurring.deleteConfirm` Xoá khoản này và lịch sử thanh toán của nó? / Delete this item and its payment history? ·
`recurring.name` Tên khoản / Name ·
`recurring.amount` Số tiền / Amount ·
`recurring.isVariable` Số tiền thay đổi hàng tháng / Amount varies monthly ·
`recurring.estimate` ước tính / estimate ·
`recurring.dayOfMonth` Ngày trả hàng tháng / Day of month ·
`recurring.isActive` Đang dùng / Active ·
`recurring.dueDate` Hạn trả / Due date ·
`recurring.paidOn` Trả ngày / Paid on ·
`recurring.dueIn` đến hạn sau / due in ·
`recurring.statusUpcoming` Chưa đến hạn / Upcoming ·
`recurring.empty` Chưa có khoản định kỳ nào / No recurring items yet ·
`recurring.cardRow` Sao kê thẻ / Card statement ·
`recurring.enterAmount` Tự nhập / Enter amount
— plus one message per `RecurringPayments.*` error code. Reuses existing
`accounts.days`, `accounts.left`, `accounts.overdue`, `accounts.dueToday`,
`accounts.dueTodayFull`, `accounts.markPaid`.

## Testing

- BE integration: CRUD + every validation code; category/sub-category
  validation (sub of another category → InvalidSubCategory); update path
  (every field, clear optionals); schedule for a month (inactive hidden,
  DayOfMonth 31 → Feb 28/29 and Nov 30, record attached only for its period,
  sort); records: create, duplicate period → 409, other user's transactionId →
  InvalidTransaction, delete record keeps the transaction, deleting the
  transaction nulls `TransactionId`, item delete cascades records; user
  isolation on every route; resources keys.
- FE: `utils/recurring.ts` (status boundaries 0/3/4 and −1, totals with paid
  vs estimate, card rows in/out of month); `toTransactionPayload` unchanged
  behaviour (TransactionsPage tests stay green); `TransactionFormModal`
  prefill test; RecurringPage (tiles, statuses, Ghi nhận → createTransaction
  then createRecord with the returned id and the edited amount, mark paid,
  undo, card row Đã trả); dashboard banner includes recurring dues.

## Data (after deploy)

Monthly items (Google Drive is billed yearly — not included):

| Name | Category | Amount | Variable | Day |
|---|---|---|---|---|
| Gửi xe ô tô + xe máy (hầm) | Xe cộ › Gửi xe | 1,600,000 | no | 2 |
| Gửi xe máy cơ quan | Xe cộ › Gửi xe | 120,000 | no | 1 |
| Tiền điện | Hóa đơn › Điện | 0 | yes | 5 |
| Tiền nước | Hóa đơn › Nước | 0 | yes | 5 |
| Phí dịch vụ chung cư | Hóa đơn › Phí chung cư | 0 | yes | 9 |
| Claude Code | Hóa đơn › Dịch vụ số | 0 | yes | 1 |
| YouTube Premium | Hóa đơn › Dịch vụ số | 165,556 | no | 1 |

Days are best guesses from November transactions; the owner adjusts them in the manage dialog.
