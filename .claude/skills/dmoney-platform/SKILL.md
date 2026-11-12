---
name: dmoney-platform
description: Use this skill when you need the bird's-eye view of the dmoney-tracker
  system - how the repos relate, cross-repo contracts, shared infrastructure, ports,
  docker compose, or deciding which service a change belongs to. Triggers include
  "architecture", "system overview", "which repo", "docker compose", "ports",
  "cross-repo", "contract", or working in the dmoney-tracker-orchestrator/ directory.
---

# dmoney-tracker Platform Skill

Personal money tracker (Vietnamese-first), 3 sibling repos, 1 user-facing web app.

## Architecture

```
┌──────────────────────┐     HTTP/JSON (axios, JWT Bearer)     ┌──────────────────────┐
│  dmoney-tracker-web  │ ────────────────────────────────────► │  dmoney-tracker-be   │
│  Vite+React+Tailwind │   VITE_API_URL → http://localhost:5113│  .NET 10 minimal API │
│  + shadcn/ui         │ ◄──────────────────────────────────── │  Clean Arch + CQRS   │
└──────────────────────┘     /resources = ALL UI labels        └──────────┬───────────┘
         :5173 dev / :8080 docker                                         │ EF Core (Npgsql)
                                                                ┌─────────▼───────────┐
                                                                │  postgres :5432      │
                                                                │  db=dmoney           │
                                                                └──────────────────────┘
```

## Repository classification

| Repo | What it is | Skill |
|---|---|---|
| `dmoney-tracker-be` | .NET 10 API: auth (JWT), transactions CRUD, monthly summary, dashboard stats, i18n resources | `dmoney-backend` |
| `dmoney-tracker-web` | React SPA: login/register, dashboard (Tổng quan), transactions (Giao dịch) | `dmoney-web` |
| `dmoney-tracker-orchestrator` | This repo: AI brain + docker compose. No product code | `dmoney-platform` |

## Cross-repo contracts (change BOTH sides together)

| Contract | Backend side | Frontend side |
|---|---|---|
| Response DTO shapes (camelCased by ASP.NET) | `src/Application/Transactions/Data/*.cs` | `src/api/types.ts` |
| Plan (Sổ) DTO + required `planId` on ALL transaction APIs (query param on reads, body field on writes/import) | `src/Application/Plans/Data/PlanResponse.cs` | `src/api/types.ts` (`PlanResponse`), `src/api/planApi.ts`, `src/plans/PlanContext.tsx` |
| Beneficiary (Đối tượng) DTO + optional `beneficiaryId` on transaction writes (debit only) and `beneficiaryId`/`beneficiaryName` on reads | `src/Application/Beneficiaries/Data/BeneficiaryResponse.cs` | `src/api/types.ts` (`BeneficiaryResponse`), `src/api/beneficiaryApi.ts`, `src/beneficiaries/` |
| Gold type (Vàng) DTO + optional `goldTypeId`/`goldQuantity` pair on transaction writes and `goldTypeId`/`goldTypeName`/`goldQuantity` on reads; `/gold/acquisitions` CRUD (pre-owned/gifted gold — quantity, unit price, note, no money flow) returns `GoldAcquisitionResponse`; `/gold/summary` merges acquisitions into each type's bought quantity/total spent/average cost and lists them under `Acquisitions` | `src/Application/GoldTypes/Data/GoldTypeResponse.cs`, `src/Application/Gold/Data/GoldSummaryResponse.cs`, `src/Application/GoldAcquisitions/Data/GoldAcquisitionResponse.cs` | `src/api/types.ts` (`GoldTypeResponse`, `GoldSummaryResponse`, `GoldAcquisitionResponse`), `src/api/goldApi.ts`, `src/gold/` |
| Purchase place (Nơi mua) DTO + `/purchase-places` CRUD (per-user catalog, delete → 409 `PurchasePlaces.InUse` while referenced); optional `purchasePlaceId` on transaction writes (gold pair required, else 400 `Transactions.PurchasePlaceRequiresGold`) and on `/gold/acquisitions` writes; `purchasePlaceId`/`purchasePlaceName` on `TransactionResponse`, `GoldTransactionResponse`, `GoldAcquisitionResponse` reads | `src/Application/PurchasePlaces/Data/PurchasePlaceResponse.cs` | `src/api/types.ts` (`PurchasePlaceResponse`), `src/api/purchasePlaceApi.ts`, `src/purchasePlaces/` |
| Bank (Ngân hàng) DTO + `/banks` CRUD + `PUT /banks/{id}/default` (per-user catalog of banks/e-wallets, single `IsDefault` — form preselects it; list ordered by user-set `SortOrder` (new banks append; `PUT /banks/order {ids}` = full list once each, else 400 `Banks.InvalidOrder`) — that order also ranks "Trả bằng" groups, top 2 shown + "Xem thêm"; delete has NO InUse guard; a rename also rewrites the owner's `Account.bankName`, transaction `bank`/`savingsBank`, recurring `bank`/`savingsBank` and savings-goal names); transaction `bank` stays free text — the catalog only feeds the form's chips (picking a chip stores the name); `AddBanks` migration seeded each user's catalog from their transactions' distinct bank strings | `src/Application/Banks/Data/BankResponse.cs` | `src/api/types.ts` (`BankResponse`), `src/api/bankApi.ts`, `src/banks/` |
| Savings (Tiết kiệm): optional free-text `savingsBank` ("Nơi gửi", ≤100, error `Transactions.SavingsBankTooLong`) on transaction writes/reads — form shows it only when the picked sub-category has code `savings_book` ("Sổ tiết kiệm" under Tích luỹ; `SubCategoryResponse.code`, coded sub-categories can't be deleted → 400 `SubCategories.SystemSubCategory`); `GET /savings/summary` (no planId param — sums `savings_book` rows of EVERY plan; `planId`/`planName` = the default plan, where the Savings page records deposits) over `savings_book` rows only, debit = deposit / credit = withdrawal, accounts grouped by `savingsBank` (null bucket last) + full history; stats/monthly chart computed client-side | `src/Application/Savings/Data/SavingsSummaryResponse.cs`, `src/Application/SubCategories/Data/SubCategoryResponse.cs`, `src/Domain/SubCategories/SubCategoryCodes.cs` | `src/api/types.ts` (`Savings*Response`, `SubCategoryResponse.code`), `src/api/savingsApi.ts`, `src/pages/SavingsPage.tsx`, `savingsMonthly` in `src/utils/chartData.ts` |
| Exclude from stats (Không tính vào thống kê): `excludeFromStats` bool on `CategoryResponse`/`SubCategoryResponse` and on POST/PUT `/categories` + `/subcategories` bodies (PUT request records hand-thread it); `excludedFromStats` on month-list `TransactionResponse` items. A transaction is excluded when its category OR sub-category is flagged, it is an advance (`isAdvance`) or it carries gold (`goldTypeId`) → left out of dashboard monthly/daily/byCategory and month `totalCredit`/`totalDebit`/`balance` (items still listed); a credit that reimburses advances counts only what exceeds them. Month-list items carry `countedCredit`/`countedDebit` (what each adds to totals) — web day/month totals and Excel totals sum those. Single rule in `TransactionStatsFilter`; gold/savings summaries unaffected. Seeded (migration `LinkStatsRules`): the savings category is excluded (savings = assets); sub-category codes `account_transfer` ("Chuyển tiền nội bộ › Chuyển giữa tài khoản", excluded) and `card_payment` ("Nợ › Trả thẻ tín dụng", counted) — the web form picks them by code (`subCategoryCode` prefill; picking a "Chuyển vào" destination with no category picks `account_transfer`) | `src/Application/Transactions/TransactionStatsFilter.cs`, `Domain/Categories/Category.cs`, `Domain/SubCategories/SubCategory.cs` | `src/api/types.ts`, `categoryApi.ts`/`subCategoryApi.ts`, `CategorySettingsPage`/`SubCategorySettingsPage` checkbox, `TransactionsPage` month card + `utils/transactionGroups.ts` day totals skip excluded rows |
| Accounts & Debt (Tài khoản & Nợ): per-user `/accounts` CRUD (`AccountResponse` with embedded `latestSnapshot`; type ∈ `checking`/`ewallet`/`cash`/`overdraft`/`credit_card`, `lastDigits` = 4 digits only — never full numbers) + snapshots `GET/POST /accounts/{id}/snapshots`, `PUT/DELETE /accounts/snapshots/{snapshotId}` (balance = money held, or amount owed for debt types; card statement amount/due date/installment/paid). Transactions carry optional `accountId` (the "Trả bằng" chip; owned by the user else 404 `Accounts.NotFound`, FK SET NULL) and optional `toAccountId` ("Chuyển vào / Trả cho" — own destination, e.g. paying a card from overdraft; money-out only → 400 `Transactions.TransferDebitOnly`, ≠ accountId → 400 `Transactions.TransferSameAccount`, owned else 404, FK SET NULL); `AccountResponse` returns `currentBalance` = latest snapshot + linked transactions recorded after it (dated later, or same day with CreatedAt after the snapshot; via accountId: debt types +debit −credit, money types +credit −debit; via toAccountId the opposite) + `transactionsSinceSnapshot` + `statementPaidAmount` (debits paid INTO the account since the reading) — nothing is ever written back to snapshots, so editing/deleting a transaction always moves balances back. There is NO pay-statement endpoint: paying a card statement = a transaction with `toAccountId` = card (Accounts "Đã trả" and Lịch thanh toán "Ghi nhận" share `cardPaymentPrefill`: tracked statement → `account_transfer`, `statementUntracked` → `card_payment`); web derives remaining = statement − `statementPaidAmount` and settled = `statementPaid` or remaining 0 (`statementRemaining`/`statementSettled`). `GET /accounts/{id}/transactions` = newest 100 linked rows across plans with signed `effect` and `afterSnapshot` (Accounts "Xem giao dịch" dialog). Totals (cash/debt/net worth) count only accounts WITH a snapshot (`countsInTotals`). Dashboard net worth = money + savings + gold at cost (held qty × avg cost) − debt, all plans (`utils/netWorth.ts`). Totals/dues derived client-side; overdue unpaid statements stay listed (`accounts.overdue`). `AccountResponse.isDefault` = pay-with default (≤1 per user, may be none) via `PUT`/`DELETE /accounts/{id}/default`; new-transaction form preselects it unless `prefill` sets a payment | `src/Domain/Accounts/*`, `src/Application/Accounts/*`, `src/Web.Api/Endpoints/Accounts/AccountEndpoints.cs` | `src/api/types.ts` (`AccountType`, `AccountResponse`, …), `src/api/accountApi.ts`, `src/utils/accounts.ts`, `src/pages/AccountsPage.tsx`, `src/accounts/*`, dashboard due banner |
| Recurring payments (Lịch thanh toán): per-user `/recurring-payments` CRUD (`RecurringPaymentResponse`: name, categoryId/subCategoryId, accountId (pay-with; owned else 404, FK SET NULL; "Ghi nhận" prefills it as `payWithAccountId`), amount, isVariable — amount 0 + variable = "Tự nhập", dayOfMonth 1–31 clamped to month end, paymentMethod code, bank, note, isActive); `GET /recurring-payments/schedule?month=YYYY-MM` → `RecurringScheduleItemResponse` { item, dueDate, record\|null } (active only); records `GET/POST /recurring-payments/{id}/records` (period `YYYY-MM`, unique per item → 409 `RecurringPayments.AlreadyPaid`, optional transactionId owned by the user), `DELETE /recurring-payments/records/{recordId}` (undo keeps the transaction); record→transaction FK SET NULL. Web "Ghi nhận" = createTransaction (pre-filled `TransactionFormModal` via `prefill`) then createRecord, deleting the transaction if the record fails; card statements shown read-only from Accounts | `src/Domain/RecurringPayments/*`, `src/Application/RecurringPayments/*`, `src/Web.Api/Endpoints/RecurringPayments/RecurringPaymentEndpoints.cs` | `src/api/types.ts` (`Recurring*`), `src/api/recurringPaymentApi.ts`, `src/utils/recurring.ts`, `src/utils/transactionPayload.ts`, `src/pages/RecurringPage.tsx`, `src/recurring/*`, dashboard banner |
| Transaction list period: `GET /transactions?planId=…&month=YYYY-MM\|YYYY` OR `&from=YYYY-MM-DD&to=YYYY-MM-DD` (inclusive, range wins over month; missing end / bad date / from>to → 400 `Transactions.InvalidDateRange`, span > 366 days → 400 `Transactions.DateRangeTooLong`). Web sends `from`/`to` only for ranges that aren't a whole month/year (Tremor `DateRangePicker` in the filters) | `src/Application/Transactions/*` (monthly summary query), `src/Web.Api/Endpoints/Transactions/*` | `src/api/transactionApi.ts` (`getMonthlySummary(period: string \| DayRange)`), `src/api/types.ts` (`DayRange`), `src/utils/dateRange.ts`, `src/components/TransactionFilters.tsx` |
| Import: `POST /transactions/import { rows, planId, accountId? }` — with accountId every row is paid with that account (moves its balance after its latest reading); web import dialog has a "Sao kê của tài khoản" select | `src/Application/Transactions/ImportTransactions*.cs` | `src/api/transactionApi.ts` (`importTransactions`), `src/components/ImportTransactionsDialog.tsx` |
| Category codes | `Domain/Transactions/TransactionCategories.cs` | `src/utils/categories.ts` |
| Payment method / card type codes | `Domain/Transactions/PaymentMethods.cs`, `CardTypes.cs` | `src/utils/paymentMethods.ts` |
| ALL UI labels + error messages | `Web.Api/Resources/SharedResource.{vi,en}.resx` served at `GET /resources?lang=` | `t(key)` via I18nContext — falls back silently to raw key |
| API base URL | serves on :5113 | `VITE_API_URL` (build arg in docker) |

## Shared infrastructure

- `docker-compose.yml` (this repo): postgres :5432 (user/pass `postgres`/`postgres`,
  db `dmoney`), api :5113 (auto-migrate on), web :8080. `docker compose up --build`.
- Local dev: postgres via `docker compose up -d postgres`, api via
  `dotnet run --project src/Web.Api`, web via `npm run dev` (:5173).
- Branch strategy: work on feature branches in each repo; `main` is default everywhere.

## Skill navigation

- Change data model / endpoint / validation / error code → `dmoney-backend`
- Change UI / page / component / chart / label usage → `dmoney-web`
- Add a user-facing string → BOTH (resx keys in be, `t()` usage in web)
- New repo → add to `REPOS` in Makefile + new skill + row in `agent_docs/skill-routing.md` + row here
