# dmoney-tracker: Gold acquisitions (Vàng có sẵn) — opening balances & gifts

**Date:** 2026-09-02
**Status:** Approved
**Repos:** `dmoney-tracker-be` + `dmoney-tracker-web`, continuing on the existing
`feature/gold` branches (open PRs be#11 / web#8 pick the commits up).
**Extends:** `2026-08-29-gold-tracking-design.md` (gold tracking v1, merged into
the same branches).

## Decisions (user-approved)

1. Gold owned BEFORE using the app (bought earlier, or gifted) must add to the
   holdings and cost statistics **without creating any money flow** — no
   credit/debit, no effect on plan balances or monthly summaries. The v1 guard
   that rejects zero-amount gold *transactions* stays: these records are a
   **separate entity**, not transactions.
2. Each record ("vàng có sẵn") is itemized: **gold type, date, quantity (chỉ),
   unit price per chỉ at that time (₫, ≥ 0), optional note** ("được tặng",
   "mua 2024"…). Gifts enter unit price 0 (or a reference value — user's
   choice). Multiple records allowed; editable and deletable.
3. Statistics merge both sources: per type, **bought quantity** and **total
   spent** include acquisitions (spent += quantity × unit price);
   **held = bought(merged) − sold**; **average cost per chỉ =
   totalSpent(merged) ÷ boughtQuantity(merged)** — a 0-price gift dilutes the
   average, matching "real capital per chỉ held". The user compares that
   average against today's market price to judge lãi/lỗ (live P&L stays a
   later phase).
4. The Gold page history table shows acquisitions **merged with transactions
   by date**, labeled **"Có sẵn"** instead of Mua/Bán, showing unit price and
   value (quantity × unit price) — visually distinct from money movements.
   Acquisition rows get inline edit/delete.

## Backend (`dmoney-tracker-be`)

- `Domain/GoldAcquisitions/GoldAcquisition.cs`: `Id`, `UserId`, `GoldTypeId`,
  `Date` (DateOnly, required), `Quantity` (decimal, > 0), `UnitPrice`
  (decimal, ≥ 0, ₫/chỉ), `Note` (nullable, trimmed, ≤ 255); `Create`,
  `Update`. `GoldAcquisitionErrors`: `QuantityInvalid`, `UnitPriceInvalid`,
  `NoteTooLong`, `NotFound` (all with codes `GoldAcquisitions.*`).
  `GoldAcquisitionConstants.NoteMaxLength = 255`.
- EF: table `gold_acquisitions`, FK → users Cascade, FK → gold_types
  **Restrict**, `HasIndex(UserId)`; `Quantity numeric(18,4)`,
  `UnitPrice numeric(18,2)`. Migration `AddGoldAcquisitions`, no hand edits.
- Endpoints (auth, CQRS like the gold-types slice):
  `GET /gold/acquisitions` (date desc, then CreatedAt desc) ·
  `POST /gold/acquisitions {goldTypeId, date, quantity, unitPrice, note}` →
  201 · `PUT /gold/acquisitions/{id}` → 204 · `DELETE /gold/acquisitions/{id}`
  → 204. Handlers verify the gold type exists and belongs to the user →
  404 `GoldTypes.NotFound`.
- `DeleteGoldTypeCommandHandler`: `InUse` guard extends to acquisitions
  (`Transactions.Any || GoldAcquisitions.Any` → 409).
- `GET /gold/summary` changes (cross-repo contract):
  - per-type math now merges acquisitions: `BoughtQuantity` = tx buys +
    acquisition quantities; `TotalSpent` = tx buy amounts +
    Σ(quantity × unitPrice); `HeldQuantity` = merged bought − sold;
    `AverageCostPerChi` = merged spent ÷ merged bought (0 when nothing).
  - response gains `Acquisitions`:
    `GoldAcquisitionResponse(Guid Id, DateOnly Date, Guid GoldTypeId,
    string GoldTypeName, decimal Quantity, MoneyResponse UnitPrice,
    MoneyResponse Value, string? Note)` — `Value` = quantity × unitPrice,
    rounded 0 dp; list ordered date desc.
- resx vi/en (both files, identical keys):
  `goldAcq.add` ("Khai báo vàng có sẵn"/"Add pre-owned gold"),
  `goldAcq.edit` ("Sửa vàng có sẵn"/"Edit pre-owned gold"),
  `goldAcq.badge` ("Có sẵn"/"Pre-owned"), `goldAcq.date` ("Ngày"/"Date"),
  `goldAcq.quantity` ("Số chỉ"/"Quantity (chỉ)"),
  `goldAcq.unitPrice` ("Đơn giá/chỉ"/"Price per chỉ"),
  `goldAcq.note` ("Ghi chú"/"Note"),
  `goldAcq.deleteConfirm` ("Xóa dòng vàng có sẵn này?"/"Delete this pre-owned
  gold entry?"),
  errors `GoldAcquisitions.QuantityInvalid` ("Số chỉ phải lớn hơn 0."/"Quantity
  must be greater than zero."), `GoldAcquisitions.UnitPriceInvalid` ("Đơn giá
  không được âm."/"Unit price cannot be negative."),
  `GoldAcquisitions.NoteTooLong` ("Ghi chú tối đa 255 ký tự."/"Note must be at
  most 255 characters."), `GoldAcquisitions.NotFound` ("Không tìm thấy dòng
  vàng có sẵn."/"Pre-owned gold entry not found.").

## Frontend (`dmoney-tracker-web`)

- types: `GoldAcquisitionResponse { id, date, goldTypeId, goldTypeName,
  quantity, unitPrice: MoneyResponse, value: MoneyResponse, note }`;
  `GoldSummaryResponse` gains `acquisitions: GoldAcquisitionResponse[]`.
- `goldApi.ts` gains `createGoldAcquisition(payload)`,
  `updateGoldAcquisition(id, payload)`, `deleteGoldAcquisition(id)` with
  `GoldAcquisitionPayload { goldTypeId, date, quantity, unitPrice, note }`
  (no list fn — the page reads them from the summary).
- `src/gold/GoldAcquisitionDialog.tsx` (create + edit modes): Select gold type
  (`useGoldTypes`), date input (default today), quantity (decimal pattern from
  the form toggle), unit price (VND digits + thousands format like the amount
  input), note Input. Save → api call → caller refreshes summary.
- GoldPage: header button `goldAcq.add` opens the dialog; history table rows
  become the merge of transactions and acquisitions sorted by date desc —
  acquisition rows: badge `goldAcq.badge`, content = note or "—", quantity,
  amount column shows `Value` (muted, no +/− or income/expense color),
  price column shows `UnitPrice`, plus edit (opens dialog prefilled) and
  delete (AlertDialog confirm) actions.
- No transaction-form or transactions-page changes.

## Verification

BE: integration tests — CRUD (+ validation 400s, foreign type 404, foreign
user 404); gold-type delete blocked by an acquisition (409) and allowed after
its deletion; summary math with mixed tx buys + acquisitions + gift (price 0)
+ sells (merged bought/spent/avg, held) and the acquisitions array shape.
Gates: `dotnet build && dotnet test`.
FE: vitest — dialog submits create payload; edit prefills and calls update;
page merges an acquisition row with badge + value and deletes after confirm.
Gates: `npm test && npm run build && npm run lint`.
Final: docker E2E + test-data cleanup (users, gold types, acquisitions,
categories) per the cleanup memory; rebuild + redeploy the stack.

## Cross-repo contract additions

dmoney-platform skill: extend the gold contract row with the acquisitions
endpoints + `GoldAcquisitionResponse` and the summary's merged-math note.

## Out of scope (later phases)

Live market price + lãi/lỗ display, importing acquisitions, per-plan
breakdowns.
