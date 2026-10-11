# dmoney-tracker: Savings (Tiết kiệm) — balance per account, from transactions

**Date:** 2026-10-11
**Status:** Approved (owner: "oke làm đi" — build, PR, deploy docker)
**Repos:** `dmoney-tracker-be` + `dmoney-tracker-web`, continuing on the existing
`feature/gold` branches (open PRs be#11 / web#8 absorb the commits).

## Decisions (user-approved)

1. New menu **Tiết kiệm** (`/app/savings`) answers: how much is in savings in
   total, and in which accounts.
2. Savings = transactions whose category has code **`savings`** ("Tích luỹ",
   global seeded category). **Debit = deposit (+)**, **credit = withdrawal
   (−)**. Balance = Σdebit − Σcredit.
3. New optional transaction field **`SavingsBank`** ("Nơi gửi") — where the
   savings are held, distinct from `Bank` (the source account the money left).
   Free text ≤ 100 like `Bank` (no FK); the form offers chips from the bank
   catalog + "＋ Khác". Example: Bank = VPBank, SavingsBank = Vietinbank.
4. **User-level across all plans (sổ)** — like gold, the summary API takes no
   `planId`.
5. Savings rows with no `SavingsBank` are grouped as one "unassigned" account
   (`savingsBank: null`, rendered "Chưa ghi nơi gửi") so the total stays right.
6. **No server guard** tying `SavingsBank` to the savings category (the BE
   cannot cheaply know a category's code in the domain, and the summary only
   reads savings-category rows anyway). The form shows the field only when
   the picked category is `savings` and submits `null` otherwise.
7. Out of scope: interest, term, maturity date, per-plan filter.

## Backend (`dmoney-tracker-be`)

- `Transaction.SavingsBank` (`string?`, column `savings_bank`, max 100).
  `TransactionConstants.SavingsBankMaxLength = 100`; error
  `Transactions.SavingsBankTooLong` (400). Normalized (trimmed, empty → null)
  like `Bank`. `Transaction.Create/Update` gain trailing
  `string? savingsBank = null`. Migration `AddTransactionSavingsBank`
  (scaffold untouched, no backfill).
- Threaded through `CreateTransactionCommand`, `UpdateTransactionCommand`,
  the hand-written `UpdateTransactionRequest` in
  `Web.Api/Endpoints/Transactions/UpdateTransaction.cs` (update-path
  regression test mandatory), and `TransactionResponse` (append
  `string? SavingsBank = null`; every projection sets it).
  Import (Excel) leaves it null.
- `GET /savings/summary` (new; `Application/Savings/GetSavingsSummaryQuery*`,
  `Web.Api/Endpoints/Savings/GetSavingsSummary.cs`, RequireAuthorization):
  ```
  SavingsSummaryResponse(
    MoneyResponse TotalBalance,
    IReadOnlyList<SavingsAccountResponse> Accounts,      // balance desc, unassigned last
    IReadOnlyList<SavingsTransactionResponse> Transactions) // date desc, then createdAt desc
  SavingsAccountResponse(string? SavingsBank, MoneyResponse Balance,
    MoneyResponse TotalDeposited, MoneyResponse TotalWithdrawn, int TransactionCount)
  SavingsTransactionResponse(Guid TransactionId, DateOnly Date, string Content,
    string? SavingsBank, string? Bank, MoneyResponse Credit, MoneyResponse Debit,
    Guid PlanId, string? SubCategoryName, string? Note)
  ```
  Filter: `t.UserId == userId && t.CategoryId` ∈ categories with
  `Code == "savings"`. Accounts with zero balance still appear (history).
  Currency = `Money.DefaultCurrency`.
- resx vi/en (identical keys/order): `menu.savings` ("Tiết kiệm"/"Savings"),
  `savings.title` ("Tiết kiệm"/"Savings"), `savings.total` ("Tổng tiết
  kiệm"/"Total savings"), `savings.accounts` ("Nơi gửi"/"Accounts"),
  `savings.deposited` ("Đã gửi"/"Deposited"), `savings.withdrawn` ("Đã
  rút"/"Withdrawn"), `savings.unassigned` ("Chưa ghi nơi gửi"/"No account
  set"), `savings.history` ("Lịch sử tiết kiệm"/"Savings history"),
  `savings.count` ("giao dịch"/"transactions"), `savings.empty` ("Chưa có
  giao dịch tích luỹ nào."/"No savings transactions yet."),
  `savings.filterAll` ("Tất cả nơi gửi"/"All accounts"), `savings.hint`
  ("Giao dịch danh mục Tích luỹ: ghi nợ = gửi vào, ghi có = rút ra."/"Savings
  category: debit = deposit, credit = withdrawal."), `form.savingsBank`
  ("Nơi gửi"/"Held at"), `export.colSavingsBank` ("Nơi gửi"/"Held at"),
  `Transactions.SavingsBankTooLong` ("Nơi gửi tối đa 100 ký tự."/"Held-at
  name must be at most 100 characters.").

## Frontend (`dmoney-tracker-web`)

- `src/api/savingsApi.ts` (`getSavingsSummary`) + types in `src/api/types.ts`
  mirroring the three records; `TransactionResponse.savingsBank: string |
  null`; `TransactionPayload.savingsBank: string | null`. Fixtures gain
  `savingsBank: null`.
- `TransactionFormModal`: when the selected category's code is `savings`,
  render a "Nơi gửi" block (chips from `useBanks()` + "＋ Khác" free text,
  same look as the bank chips, no default preselect). Hidden and submitted as
  `null` for any other category; edit mode restores the stored value.
- `TransactionsPage`: savings rows with `savingsBank` show a small chip
  "→ {savingsBank}" next to the existing bank chip. Excel export gains the
  `export.colSavingsBank` column.
- New page **Tiết kiệm** `/app/savings` (sidebar after Vàng, lucide
  `PiggyBank`): big total card (+ hint text); grid of account cards (name or
  `savings.unassigned`, balance, deposited / withdrawn, count) — clicking a
  card filters the history; history list (date, content, account, ±amount,
  sub-category/note muted) with a filter Select (`savings.filterAll`).
  Empty state `savings.empty`.

## Verification

BE integration tests: summary groups per SavingsBank with unassigned bucket,
deposit/withdrawal math, only `savings`-category rows counted, other users'
rows excluded, across plans; create + update round-trip `SavingsBank`
(update-path threading test); >100 chars → 400. Gates: `dotnet build` (zero
warnings) + `dotnet test`.
FE vitest: form shows Nơi gửi only for savings category and submits it/null;
Savings page renders total, accounts, unassigned label, filter by card.
Gates: `npm test && npm run build && npm run lint`.
Final: docker rebuild + smoke check of `/savings/summary` + UI, E2E test data
cleanup, platform-skill contract row, PR comments via MCP (not gh).
