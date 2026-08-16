# dmoney-tracker: Plans (Sổ) — separate ledgers per user

**Date:** 2026-08-16
**Status:** Approved
**Repos:** `dmoney-tracker-be` (branch `feature/plans` off `feature/import-transactions`), `dmoney-tracker-web` (branch `feature/plans` off `feature/import-transactions`)

## Decisions (user-approved)

1. A plan is a **separate ledger (sổ riêng / workspace)**: every screen shows only the
   selected plan; new transactions default into it. Not an event tag, not a budget.
2. Existing transactions are backfilled into an auto-created default plan **"Sổ chính"**
   (`IsDefault = true`, renamable, never deletable). Every user always has exactly one.
3. **No combined "all plans" view** — one plan at a time; switching is the only way to
   see another ledger.
4. Switcher is a **header dropdown** (visible on every screen) with "+ Tạo sổ mới" and a
   link to a management page; management page lives at `/app/settings/plans`.
5. Transactions **can move between plans** via a plan select in the edit form (create
   always uses the selected plan implicitly).
6. Implementation shape: **`plan_id` NOT NULL** on transactions (no nullable/implicit
   default semantics).

## Backend (`dmoney-tracker-be`)

- `Domain/Plans/Plan.cs`: `Id`, `UserId`, `Name` (required, trimmed, ≤ 100),
  `IsDefault`; `PlanErrors` — `NameRequired`, `NameTooLong`, `NotFound`, `NotEmpty`,
  `CannotDeleteDefault`.
- `Transaction.PlanId` (Guid, required) added to `Create`/`Update`; EF config: FK to
  `plans`, index `(user_id, plan_id)`.
- **Migration** (single migration, runs under auto-migrate): create `plans`; insert one
  `"Sổ chính"` (`IsDefault = true`) per existing user (SQL over `users`); backfill
  `transactions.plan_id` from the owner's default plan; then set NOT NULL + FK.
- Registration handler also creates the user's default plan.
- New endpoints (all `RequireAuthorization`, CQRS like Categories):
  `GET /plans` (default first, then by name) · `POST /plans {name}` ·
  `PUT /plans/{id} {name}` · `DELETE /plans/{id}` — delete rejected for the default plan
  (`Plans.CannotDeleteDefault`) or a plan that still has transactions (`Plans.NotEmpty`).
- Ownership guard everywhere: a `planId` that doesn't exist or belongs to another user →
  `Plans.NotFound`.
- Existing reads take a required `planId` query param and filter by it:
  `GET /transactions?month=` (monthly summary), `GET /transactions/stats`,
  `GET /transactions/advances/open`, `GET /transactions/prepaid`,
  `GET /transactions/credits`. `POST /transactions`, `PUT /transactions/{id}` and
  `POST /transactions/import` take `planId` in the body (update with a different
  `planId` = move between ledgers).
- Advance/reimbursement and prepaid links only connect transactions **within one plan**;
  moving a transaction that still holds a cross-plan link is rejected with a clear error.
- resx (vi/en): `menu.plans`, `plans.*` UI labels (title, create, rename, delete,
  defaultBadge, empty, deleteConfirm, switcherLabel, manage) + descriptions for the new
  error codes.

## Frontend (`dmoney-tracker-web`)

- `src/api/planApi.ts` (CRUD) + `PlanResponse { id, name, isDefault }` in
  `src/api/types.ts`.
- `src/plans/PlanContext.tsx`: loads plans after auth; `plans`, `selectedPlanId`,
  `selectPlan`, `refresh`. Selection persisted under a new `STORAGE_KEYS.planId`;
  stored id no longer in the list (deleted elsewhere / `Plans.NotFound` from any call) →
  fall back to the default plan and refresh the list.
- Header (AppLayout): plan dropdown next to the nav — plan list, "+ Tạo sổ mới" item
  (name dialog; on create, switch to the new plan immediately), "Quản lý sổ" item
  linking to `/app/settings/plans`.
- `/app/settings/plans` page (pattern: CategorySettingsPage): list with default badge,
  rename inline, delete (hidden/disabled for the default plan and non-empty plans),
  create.
- All plan-scoped calls pass `selectedPlanId` from context: dashboard stats, monthly
  summary, advances/prepaid pickers, import (dialog states the target plan's name),
  create/update transaction. Export exports the current summary → already plan-scoped.
- TransactionFormModal: create → hidden, uses selected plan; edit → plan Select
  defaulting to the transaction's plan.
- Switching plan refetches the visible page (summary/dashboard react to
  `selectedPlanId`).

## Verification

BE: integration tests — plans CRUD; default plan exists after registration; delete
guards (default, non-empty); monthly summary/dashboard/pickers filter by `planId`;
cross-user `planId` rejected; move transaction between plans via update. Gates:
`dotnet build` + tests.
FE: vitest — PlanContext selection/fallback, header switcher renders and switches,
TransactionsPage refetches on plan change, edit form sends changed `planId`, plans
settings page CRUD. Gates: `npm test && npm run build && npm run lint`.
Final: docker stack — create second plan, add transactions in both, switch and verify
isolation, move one transaction, verify default-plan delete is blocked.

## Out of scope (later phases)

Combined all-plans view, per-plan budgets/targets, sharing plans between users,
archiving plans, bulk-move of transactions between plans.
