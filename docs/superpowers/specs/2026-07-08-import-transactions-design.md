# dmoney-tracker: Import transactions from CSV/XLSX

**Date:** 2026-07-08
**Status:** Approved
**Repos:** `dmoney-tracker-be` (branch `feature/import-transactions` off `feature/payment-method`), `dmoney-tracker-web` (branch `feature/import-transactions` off `feature/tailwind-redesign`)

## Decisions (user-approved)

1. Single signed amount column: **negative = Ghi nợ (debit), positive = Ghi có (credit)**.
2. **FE parses** (SheetJS `xlsx` package reads both .csv and .xlsx) with a preview table; BE exposes a JSON bulk endpoint.
3. Invalid rows are flagged red in the preview with a reason and **excluded**; only valid rows are imported. Final toast reports imported/skipped counts.
4. Category defaults to `other`; payment method defaults to `transfer`. Column-mapping / editing of imports is a later phase.

## File format (position-based columns)

| Col | Field | Accepted values |
|---|---|---|
| 1 | Date | Excel date cell, `DD/MM/YYYY`, `YYYY-MM-DD` |
| 2 | Content | non-empty string (≤500 after trim) |
| 3 | Amount | signed number; thousand separators `.` or `,` tolerated (`1.200.000`, `-1,200,000`, `-50000`); zero is invalid |
| 4 | Note | optional (≤1000) |

Header row auto-skipped when its amount cell does not parse as a number.

## Backend

- `ImportTransactionsCommand(IReadOnlyList<ImportTransactionRow> Rows) : ICommand<int>`; row = `(DateOnly Date, string Content, decimal Amount, string? Note)`.
- Handler: auth via `IUserContext`; guards — empty list → `Transactions.ImportEmpty`, > `TransactionConstants.ImportMaxRows` (1000) → `Transactions.ImportTooManyRows`; per row map `Amount >= 0 → credit`, `< 0 → debit = |amount|`, category `TransactionCategories.Other`, then `Transaction.Create` (defense in depth — first failing row aborts with its error); single `SaveChangesAsync`.
- Endpoint `POST /transactions/import` (`RequireAuthorization`), body binds the command, returns `200 { imported }`.
- resx (vi/en): error descriptions for the two new codes + FE labels `import.*` (title, hint, chooseFile, colDate/colContent/colAmount/colNote, rowsValid, rowsInvalid, save, success, skipped, errInvalidDate, errInvalidAmount, errEmptyContent).

## Frontend

- Dep: `xlsx` (SheetJS CE).
- `src/utils/importParser.ts` (pure, unit-tested): `parseImportRows(rows: unknown[][]): { valid: ImportRow[]; invalid: InvalidRow[] }` — date/amount/content validation per the table above, header auto-skip, `ImportRow = { date: string; content: string; amount: number; note: string | null }`.
- `src/components/ImportTransactionsDialog.tsx`: shadcn Dialog — file input (`.csv,.xlsx`), SheetJS `read(await file.arrayBuffer())` + `sheet_to_json(sheet, { header: 1, raw: true })` → `parseImportRows` → preview table (invalid rows highlighted with reason, `text-expense`), footer button "…save (n)" disabled when n=0 → `importTransactions(valid)` → toast success (imported/skipped) → close + notify parent to reload.
- `importTransactions(rows)` in `src/api/transactionApi.ts` → POST `/transactions/import`.
- Entry point: button (Upload icon, `import.title`) next to "＋ Giao dịch mới" on TransactionsPage.

## Verification

BE: unit tests (sign mapping, category default, empty/too-many/invalid-row guards) + integration test (import 2 rows → GET shows credit & debit with category `other`). FE: parser unit tests (both date formats, Excel serial date, signed/thousand-separator amounts, header skip, error rows); gates `npm run build && npm test`. Final: docker stack import of a real sample CSV and XLSX.

## Out of scope (later phases)

Column mapping UI, editing imported rows in the preview, duplicate detection, category inference.
