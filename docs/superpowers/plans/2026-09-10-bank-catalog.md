# Bank Catalog (Danh mục ngân hàng) Implementation Plan

**Goal:** Per-user bank/wallet catalog (Settings → Ngân hàng) feeding the
transaction form's bank chips; transactions keep the free-text `Bank` contract.

**Spec:** `docs/superpowers/specs/2026-09-10-bank-catalog-design.md` — resx
block and error codes there are verbatim requirements.

## Global Constraints

- Repos: BE `../dmoney-tracker-be`, FE `../dmoney-tracker-web`, both on
  `feature/gold`. Mirror the PurchasePlaces slice minus the InUse guard and
  minus any transaction FK. Gates per repo as usual; E2E + cleanup + deploy +
  platform-skill row + PR comments via MCP at the end.

### Task 1: BE — Bank slice (entity, table, CRUD, seeding migration)

- [ ] Clone the PurchasePlaces slice → Banks (Domain trio minus InUse,
  EF config, commands/handlers/query, endpoints, DI, DbSet). Migration
  `AddBanks` + `Sql()` seeding distinct non-empty `transactions.Bank` per
  user. TDD off `PurchasePlacesEndpointsTests` (delete: plain 204, no 409
  case). Gates → commit `feat: bank catalog entity and crud endpoints`.

### Task 2: BE — resx keys, push

- [ ] 11 keys from the spec (4 error + 7 UI), identical order both files.
  Gates → commit `feat: bank catalog resx keys (vi/en)` → push.

### Task 3: FE — api, context, settings page

- [ ] Clone the purchase-places set (bankApi, BanksContext + test,
  CreateBankDialog, BankSettingsPage + test, route
  `settings/banks`, sidebar `menu.banks` with `Landmark`, provider inside
  PurchasePlacesProvider). Gates → commit `feat: bank settings page`.

### Task 4: FE — form chips from catalog, push

- [ ] `TransactionFormModal`: chips from `useBanks()` (mock the context in
  tests), first-letter avatar colored from a name-hash palette, custom-input
  toggle unchanged, edit-prefill custom detection against catalog names;
  delete `BANK_PRESETS`. Gates → commit
  `feat: bank chips from the user catalog` → push.

### Task 5: E2E, cleanup, deploy, docs

- [ ] Stack rebuild; throwaway-user E2E (bank CRUD + duplicate 409 + foreign
  404 + tx with picked bank name round-trip + seeding check via SQL);
  cleanup (0 test users); platform-skill contract row; orchestrator commit +
  push; PR comments be#11/web#8 via MCP.
