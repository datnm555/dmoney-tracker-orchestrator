# dmoney-tracker: Beneficiaries (Đối tượng) — who each expense is for

**Date:** 2026-08-22
**Status:** Approved
**Repos:** `dmoney-tracker-be` (branch `feature/beneficiaries` off `feature/plans`), `dmoney-tracker-web` (branch `feature/beneficiaries` off `feature/plans`)

## Decisions (user-approved)

1. A beneficiary ("đối tượng") records **who a money-out transaction is for** (Tôi,
   Vợ, Con, Bố mẹ…). **Debit only** — credits never carry one.
2. **Optional** on debit; the form pre-selects the user's default beneficiary
   (clearable). Old transactions stay beneficiary-less — no backfill.
3. Beneficiaries are **per-user, shared across all plans** (like categories).
4. Reporting = **filter on the Transactions page** only; the filtered summary card
   already shows per-selection totals. Dashboard charts are out of scope.
5. Full entity slice mirroring the Plans module, including a **set-default**
   endpoint (mirror of `PUT /plans/{id}/default`).

## Backend (`dmoney-tracker-be`)

- `Domain/Beneficiaries/Beneficiary.cs`: `Id`, `UserId`, `Name` (required, trimmed,
  ≤ 100, unique per user), `IsDefault`; `Create`, `Rename`. `BeneficiaryErrors`:
  `NameRequired`, `NameTooLong`, `Duplicate`, `NotFound`, `InUse`.
- No seeding — the user creates their own list in Settings.
- Endpoints (all `RequireAuthorization`, CQRS like Plans):
  `GET /beneficiaries` (default first, then name) · `POST /beneficiaries {name}` ·
  `PUT /beneficiaries/{id} {name}` · `DELETE /beneficiaries/{id}` (referenced by any
  transaction → 409 `Beneficiaries.InUse`) · `PUT /beneficiaries/{id}/default`
  (sets `IsDefault`, clears the previous default; mirrors the plans endpoint).
  Deleting the default beneficiary (while unreferenced) is allowed — the user then
  simply has no default until they set another; the form pre-selects nothing.
- `Transaction.BeneficiaryId` (Guid?, **nullable**), FK Restrict, migration without
  backfill. Create/Update validation when `beneficiaryId` present:
  must exist and belong to the user → else `Beneficiaries.NotFound` (404);
  only allowed when `DebitAmount > 0` → else `Transactions.BeneficiaryDebitOnly` (400).
- `TransactionResponse` gains `beneficiaryId` + `beneficiaryName` (projected like
  `subCategoryName`). No new query params — filtering is client-side.
- resx vi/en: `menu.beneficiaries` ("Đối tượng"/"People"), `beneficiaries.*` labels
  (title, create, name, rename, delete, deleteConfirm, default, setDefault, none),
  `form.beneficiary`, `filters.beneficiary`, `beneficiaries.none` (supersedes the
  earlier `filters.noBeneficiary` draft key),
  `export.colBeneficiary` + descriptions for the new error codes.

## Frontend (`dmoney-tracker-web`)

- `src/api/beneficiaryApi.ts` (CRUD + `setDefaultBeneficiary`) +
  `BeneficiaryResponse { id, name, isDefault }` in `src/api/types.ts`;
  `TransactionResponse` gains `beneficiaryId`/`beneficiaryName`;
  `TransactionPayload.beneficiaryId: string | null`.
- `src/beneficiaries/BeneficiariesContext.tsx` (pattern: CategoriesContext):
  `beneficiaries`, `refresh` — consumed by form, filter and settings page.
- Settings page `/app/settings/beneficiaries` (pattern: plans settings incl. its
  set-default button): list with default badge, create, inline rename,
  set-default, delete (surface `InUse` error toast).
- TransactionFormModal: when type = **out**, show Select "Đối tượng" — options
  "—" (none) + beneficiaries; create mode pre-selects the default beneficiary;
  edit mode shows the stored one. Type = **in** hides the field and submits null
  (switching out→in clears it).
- TransactionsPage: filter Select "Đối tượng" (Tất cả / Không có / each person),
  client-side over `tx.beneficiaryId` like the category filter — the summary card
  then shows that person's totals for the selected month/year. Debit rows with a
  beneficiary render a name chip next to the category chip. Excel export gains a
  "Đối tượng" column.
- Import: rows carry no beneficiary (out of scope to map them).

## Verification

BE: integration tests — CRUD + default-first ordering; set-default swaps the flag;
delete blocked while referenced (`InUse`) and allowed after unlink; beneficiary on
credit → 400; foreign/unknown beneficiary → 404; response carries
beneficiaryId/Name. Gates: `dotnet build` + `dotnet test`.
FE: vitest — form shows/hides by type and pre-selects default; switching to credit
clears it; filter narrows list + totals; settings page CRUD + set-default.
Gates: `npm test && npm run build && npm run lint`.
Final: docker E2E against the live stack, then **delete all E2E test data**
(users, and any beneficiaries/categories created) per the cleanup memory.

## Out of scope (later phases)

Dashboard breakdown by beneficiary, import-column mapping, per-plan beneficiary
lists, beneficiary on credits.
