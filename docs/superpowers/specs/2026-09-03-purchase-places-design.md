# dmoney-tracker: Purchase places (Nơi mua) for gold

**Date:** 2026-09-03
**Status:** Approved
**Repos:** `dmoney-tracker-be` + `dmoney-tracker-web`, continuing on the existing
`feature/gold` branches (open PRs be#11 / web#8 absorb the commits).
**Extends:** gold tracking v1 (2026-08-29) and gold acquisitions (2026-09-02).

## Decisions (user-approved)

1. A **PurchasePlace** ("nơi mua") is a per-user catalog entry (tiệm/cửa hàng
   vàng: "SJC Trần Nhân Tông", "PNJ"…) managed in **Settings → Nơi mua** —
   same shape as gold types: name required/trimmed/≤100/unique per user, no
   default, rename/delete, delete blocked (409 `PurchasePlaces.InUse`) while
   referenced by any transaction or acquisition.
2. Attached **optionally** in BOTH gold entry points:
   - the gold-acquisition dialog on /app/gold (`GoldAcquisition.PurchasePlaceId`);
   - the transaction form's gold block (`Transaction.PurchasePlaceId`) — valid
     only when the gold pair is present (buy AND sell alike; for a sell it
     reads as "nơi bán") → else 400 `Transactions.PurchasePlaceRequiresGold`.
   Old rows stay place-less; no backfill; empty renders as nothing.
3. The Gold page history shows the place name as small muted text next to the
   gold-type name on BOTH row kinds; editing a row can change it.

## Backend (`dmoney-tracker-be`)

- `Domain/PurchasePlaces/{PurchasePlace,PurchasePlaceConstants,PurchasePlaceErrors}.cs`
  — exact mirror of the GoldTypes trio (`NameMaxLength = 100`; errors
  `PurchasePlaces.{NameRequired,NameTooLong,Duplicate,NotFound,InUse}`).
- EF: table `purchase_places`, FK users Cascade, `HasIndex(UserId)`; nullable
  `PurchasePlaceId` FK **Restrict** added to `transactions` AND
  `gold_acquisitions`. Migrations `AddPurchasePlaces` then
  `AddPurchasePlaceRefs` (scaffolds untouched).
- Endpoints (mirror the gold-types slice): `GET /purchase-places` (name
  order) · `POST /purchase-places {name}` · `PUT /purchase-places/{id}` ·
  `DELETE /purchase-places/{id}` (guard: transactions OR acquisitions → 409).
  `PurchasePlaceResponse(Guid Id, string Name)`.
- `Transaction.Create/Update` gain trailing `Guid? purchasePlaceId = null`;
  guard after the gold guards: place present but `goldTypeId` null → 400
  `Transactions.PurchasePlaceRequiresGold`. Create/Update handlers add the
  ownership check (→ 404 `PurchasePlaces.NotFound`); `UpdateTransactionRequest`
  hand-threads the new field (regression test mandatory, per memory).
- `GoldAcquisition.Create/Update` gain trailing `Guid? purchasePlaceId = null`
  (no extra guard — always optional); handlers add the ownership check;
  `UpdateGoldAcquisitionRequest` threads it.
- Response contracts (cross-repo): `TransactionResponse`,
  `GoldTransactionResponse` (summary history rows) and
  `GoldAcquisitionResponse` each append
  `Guid? PurchasePlaceId = null, string? PurchasePlaceName = null` (name via
  the usual correlated subquery).
- resx vi/en (identical keys/order both files):
  `PurchasePlaces.NameRequired` ("Vui lòng nhập tên nơi mua."/"Please enter a
  name for the purchase place."), `PurchasePlaces.NameTooLong` ("Tên nơi mua
  tối đa 100 ký tự."/"Name must be at most 100 characters."),
  `PurchasePlaces.Duplicate` ("Nơi mua này đã tồn tại."/"This purchase place
  already exists."), `PurchasePlaces.NotFound` ("Không tìm thấy nơi
  mua."/"Purchase place not found."), `PurchasePlaces.InUse` ("Nơi mua đang
  được dùng bởi các dòng vàng, không thể xóa."/"This purchase place is used by
  gold entries and cannot be deleted."),
  `Transactions.PurchasePlaceRequiresGold` ("Nơi mua chỉ áp dụng cho giao dịch
  vàng."/"A purchase place only applies to gold transactions."),
  `menu.purchasePlaces` ("Nơi mua"/"Purchase places"), `purchasePlaces.title`
  ("Quản lý nơi mua"/"Manage purchase places"), `purchasePlaces.create` ("Thêm
  nơi mua"/"Add purchase place"), `purchasePlaces.name` ("Tên nơi mua"/
  "Purchase place name"), `purchasePlaces.rename` ("Đổi tên"/"Rename"),
  `purchasePlaces.delete` ("Xóa nơi mua"/"Delete purchase place"),
  `purchasePlaces.deleteConfirm` ("Xóa nơi mua này?"/"Delete this purchase
  place?"), `form.purchasePlace` ("Nơi mua"/"Purchase place").

## Frontend (`dmoney-tracker-web`)

- `src/api/purchasePlaceApi.ts` (CRUD, mirror goldApi's gold-type fns) +
  `PurchasePlaceResponse { id, name }`; `TransactionResponse`/
  `GoldTransactionResponse`/`GoldAcquisitionResponse` gain
  `purchasePlaceId`/`purchasePlaceName` (string | null); `TransactionPayload`
  and `GoldAcquisitionPayload` gain `purchasePlaceId: string | null`.
- `src/purchasePlaces/PurchasePlacesContext.tsx` (+ create dialog) and
  settings page `/app/settings/purchase-places` — clones of the gold-types
  set; sidebar entry `menu.purchasePlaces` (lucide `Store` icon); provider
  mounted inside `GoldTypesProvider`.
- Selects (optional, `'none'` sentinel → null): in `GoldAcquisitionDialog`
  and in the transaction form's gold block (cleared when the toggle turns
  off; submitted null when gold off).
- Gold page history: both row kinds render
  `{goldTypeName}` + small muted ` · {purchasePlaceName}` when present.
- Existing `TransactionResponse` fixtures gain the two null fields (compile).

## Verification

BE: integration tests — place CRUD/uniqueness/ordering; InUse guard from BOTH
sources (tx and acquisition) with unlink-then-delete; tx guard
(place without gold → 400; unknown/foreign place → 404); update-path threading
tests for BOTH `PUT /transactions/{id}` and `PUT /gold/acquisitions/{id}`;
projections round-trip place id+name in transactions list, gold summary
history and acquisitions. Gates: `dotnet build && dotnet test`.
FE: vitest — settings CRUD; both selects submit/clear the id; history shows
the place text. Gates: `npm test && npm run build && npm run lint`.
Final: docker E2E + mandatory cleanup + stack rebuild/redeploy + platform-
skill contract row update + PR comments (MCP, not gh).

## Out of scope (later)

Per-place statistics/filtering, required-place mode, places on non-gold
transactions.
