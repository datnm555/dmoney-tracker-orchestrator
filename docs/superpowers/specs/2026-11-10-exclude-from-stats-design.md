# Exclude from stats (Không tính vào thống kê) — Design

## Problem

Dashboard (Tổng quan) and month totals sum every transaction. Internal
transfers (Chuyển tiền nội bộ) and loan principal (Nợ › Cho vay / Thu hồi nợ /
Vay vào / Trả nợ vay / Thấu chi) are not real income/spending, so Nov 2026
shows Thu 226tr / Chi 168tr instead of ~78.8tr / ~22.7tr.

## Decision

A boolean `ExcludeFromStats` on **both** `Category` and `SubCategory`
(default `false`). A transaction is **excluded** when its category OR its
sub-category has the flag. Excluded rows still list normally on the
Transactions page (with a "Không tính" badge) but are left out of every total
and chart.

## Backend (`dmoney-tracker-be`)

- Domain: `Category.ExcludeFromStats`, `SubCategory.ExcludeFromStats`
  (`bool`, private set). `Category.Create(..., bool excludeFromStats = false)`,
  `Category.Update(name, icon, updatedBy, bool excludeFromStats = false)`;
  `SubCategory.Create(..., bool excludeFromStats = false)`,
  `SubCategory.Update(name, isDefault, icon, updatedBy, bool excludeFromStats = false)`.
- Migration `AddExcludeFromStats` (two non-null bool columns, default false).
- Commands (trailing optional `bool ExcludeFromStats = false`):
  `CreateCategoryCommand`, `UpdateCategoryCommand`, `CreateSubCategoryCommand`,
  `UpdateSubCategoryCommand`. The explicit endpoint request records
  `UpdateCategoryRequest` and `UpdateSubCategoryRequest` MUST thread it
  (update-path integration test required).
- Responses (trailing optional): `CategoryResponse(..., bool ExcludeFromStats = false)`,
  `SubCategoryResponse(..., bool ExcludeFromStats = false)`,
  `TransactionResponse(..., bool ExcludedFromStats = false)` — set in the
  month-list projection (`GetTransactionsByMonthQueryHandler`); other
  projections keep the default.
- Shared predicate (one place, EF-translatable), e.g.
  `IQueryable<Transaction> CountedInStats(this IQueryable<Transaction>, IApplicationDbContext)`:
  `!db.Categories.Any(c => c.Id == t.CategoryId && c.ExcludeFromStats) &&
   !db.SubCategories.Any(s => s.Id == t.SubCategoryId && s.ExcludeFromStats)`.
- Applied to: `GetDashboardStatsQueryHandler` (monthly, daily, byCategory) and
  the `TotalCredit` / `TotalDebit` / `Balance` of `MonthlySummaryResponse`
  (items list unchanged). Gold and savings summaries are NOT affected.
- resx (vi / en, same order, both files):
  - `cat.excludeFromStats` — "Không tính vào thống kê" / "Exclude from stats"
  - `cat.excludeFromStatsHint` — "Giao dịch thuộc mục này vẫn hiện trong danh sách nhưng không cộng vào tổng thu chi và biểu đồ." / "Transactions here still list but are left out of income/expense totals and charts."
  - `summary.excludedBadge` — "Không tính" / "Not counted"

## Frontend (`dmoney-tracker-web`)

- `types.ts`: `CategoryResponse.excludeFromStats: boolean`,
  `SubCategoryResponse.excludeFromStats: boolean`,
  `TransactionResponse.excludedFromStats: boolean`.
- `categoryApi` / `subCategoryApi` create+update send `excludeFromStats`.
- `CategorySettingsPage` / `SubCategorySettingsPage` dialogs: a checkbox
  `cat.excludeFromStats` with the hint line; editing pre-fills it; the list
  row shows a small `summary.excludedBadge` chip when flagged.
- `TransactionsPage`: the month card totals (computed client-side from
  `items`) skip `excludedFromStats` rows; each such row shows the
  `summary.excludedBadge` chip.
- Dashboard needs no logic change (server totals already exclude).

## Data (after deploy)

Flag category "Chuyển tiền nội bộ"; flag sub-categories Nợ › Cho vay,
Thu hồi nợ, Vay vào, Trả nợ vay, Thấu chi. Not flagged: Lãi vay / thấu chi,
Trả thẻ tín dụng.
