# dmoney-tracker: Bank catalog (Danh mục ngân hàng)

**Date:** 2026-09-10
**Status:** Approved (owner asked: replace hardcoded Techcombank/VPBank with a
user-managed list that can hold other banks or wallets like MoMo)
**Repos:** `dmoney-tracker-be` + `dmoney-tracker-web`, continuing on the
existing `feature/gold` branches (open PRs be#11 / web#8 absorb the commits).

## Decisions

1. A **Bank** ("ngân hàng" — banks and e-wallets alike) is a per-user catalog
   entry managed in **Settings → Ngân hàng** — same shape as purchase places:
   name required/trimmed/≤100/unique per user, rename/delete.
2. **Transactions keep storing `Bank` as free text** (existing contract, no
   schema change, no FK). The catalog only feeds the transaction form's bank
   chips; picking a chip stores the bank *name*. Therefore there is **no
   InUse delete guard** — deleting a catalog entry never touches old rows,
   they keep displaying their stored string.
3. The form's "＋ Khác" free-text input stays for one-off values.
4. Migration seeding: `AddBanks` seeds each user's catalog from the distinct
   non-empty `Bank` strings already on their transactions (continuity — the
   two old presets appear automatically for users who used them).
5. Chip avatar: first letter on a deterministic color from a small palette
   (hash of name) — replaces the hardcoded red/green.

## Backend (`dmoney-tracker-be`)

- `Domain/Banks/{Bank,BankConstants,BankErrors}.cs` — mirror of the
  PurchasePlaces trio minus `InUse` (`NameMaxLength = 100`; errors
  `Banks.{NameRequired,NameTooLong,Duplicate,NotFound}`).
- EF: table `banks`, FK users Cascade, `HasIndex(UserId)`. Migration
  `AddBanks` (scaffold + a `Sql()` seeding block in `Up`; nothing in `Down`
  beyond the table drop).
- Endpoints (mirror purchase-places): `GET /banks` (name order) ·
  `POST /banks {name}` · `PUT /banks/{id}` · `DELETE /banks/{id}` (no guard).
  `BankResponse(Guid Id, string Name)`.
- resx vi/en (identical keys/order both files): `Banks.NameRequired`
  ("Vui lòng nhập tên ngân hàng."/"Please enter a bank name."),
  `Banks.NameTooLong` ("Tên ngân hàng tối đa 100 ký tự."/"Name must be at
  most 100 characters."), `Banks.Duplicate` ("Ngân hàng này đã tồn
  tại."/"This bank already exists."), `Banks.NotFound` ("Không tìm thấy ngân
  hàng."/"Bank not found."), `menu.banks` ("Ngân hàng"/"Banks"),
  `banks.title` ("Quản lý ngân hàng"/"Manage banks"), `banks.create` ("Thêm
  ngân hàng"/"Add bank"), `banks.name` ("Tên ngân hàng"/"Bank name"),
  `banks.rename` ("Đổi tên"/"Rename"), `banks.delete` ("Xóa ngân
  hàng"/"Delete bank"), `banks.deleteConfirm` ("Xóa ngân hàng này?"/"Delete
  this bank?").

## Frontend (`dmoney-tracker-web`)

- `src/api/bankApi.ts` (CRUD) + `BankResponse { id, name }` in
  `src/api/types.ts`.
- `src/banks/BanksContext.tsx` (+ create dialog) and settings page
  `/app/settings/banks` — clones of the purchase-places set; sidebar entry
  `menu.banks` (lucide `Landmark` icon); provider mounted inside
  `PurchasePlacesProvider`.
- `TransactionFormModal`: chips render from `useBanks()` (names), custom
  input unchanged; `BANK_PRESETS` deleted from `utils/paymentMethods.ts`.
- Display sites (`TransactionsPage` bank chip, `paymentLabel.ts`) untouched —
  they already render the free-text string.

## Verification

BE: integration tests — bank CRUD/uniqueness/ordering/foreign-user 404;
delete referenced-by-nothing (no guard) 204. Gates: `dotnet build &&
dotnet test`. FE: vitest — context, settings page, form chips from catalog +
custom input. Gates: `npm test && npm run build && npm run lint`.
Final: docker E2E + cleanup + stack rebuild + platform-skill contract row +
PR comments (MCP).

## Addendum 2026-09-11: default bank (owner request)

Mirrors the beneficiary default: `Bank.IsDefault` (single per user, no
auto-default on create), `PUT /banks/{id}/default` switches it, `GET /banks`
orders default first then name, `BankResponse` gains `IsDefault`. Migration
`AddBankIsDefault` (no backfill). resx: `banks.default` ("Mặc
định"/"Default"), `banks.setDefault` ("Đặt mặc định"/"Set default"). FE:
settings badge + star button; the transaction form preselects the default
bank's chip on a new transaction (editing keeps the stored value).

## Out of scope

Logos per bank, account numbers/balances, bank on cash payments.
