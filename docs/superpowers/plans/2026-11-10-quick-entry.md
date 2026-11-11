# Quick Entry (popup tạo giao dịch) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the transaction create/edit popup faster for the owner's daily entry: reorder fields with rarely used sections collapsed, a "Trả bằng" chip row from Accounts, suggestions from past transactions, and input shortcuts.

**Architecture:** One new read-only backend endpoint (`GET /transactions/suggestions`) + resx keys; everything else is a frontend change to `TransactionFormModal` (no payload/DTO change — chips and suggestions only fill existing form fields).

**Tech Stack:** unchanged.

**Spec (approved in chat, binding — owner chose items 1–4):**
1. Reorder: Thu/Chi → **Số tiền** (large, first) → Nội dung → Danh mục → Danh mục con (→ Nơi gửi when savings_book) → **Trả bằng** → Ngày → Ghi chú. Vàng, Đối tượng, Ứng trước, Trả trước (and their sub-fields) move into a collapsible **"Tuỳ chọn khác"** section, collapsed by default, auto-expanded when editing a transaction that uses any of them (gold, beneficiary set & not the default, advance, prepaid/alreadyPrepaid, reimburse) or when a validation error is inside it.
2. **Trả bằng** chips from `getAccounts()` (Accounts feature): one chip per account (name, •••last4 if set), plus a "Tiền mặt" chip if no `cash` account exists. Picking a chip sets: credit_card → paymentMethod `card`, cardType `credit`, bank = account.bankName; checking/overdraft/ewallet → paymentMethod `transfer`, bank = account.bankName; cash → paymentMethod `cash`, bank null. A chip shows selected when the current paymentMethod/cardType/bank match it (first match wins). The existing payment-method / card-type / bank controls stay available below under a small "Khác" toggle for cases not covered (debit card, other bank). No new transaction field.
3. **Suggestions**: `GET /transactions/suggestions?q=<text>&limit=8` (auth, user-scoped, ALL of the user's plans): case-insensitive "contains" match on Content (trimmed q, min 2 chars else empty list), one row per distinct Content (case-insensitive) — the most recent transaction (Date desc, CreatedAt desc) — ordered by that date desc, max `limit` (1–20, default 8). Response `TransactionSuggestionResponse(string Content, string Type /* "in" | "out" */, MoneyResponse Amount, Guid? CategoryId, Guid? SubCategoryId, string PaymentMethod, string? CardType, string? Bank)`. FE: while typing in Nội dung (create mode only, debounced 250 ms), show a dropdown under the field; picking a suggestion fills content, type, amount, category, sub-category, payment method, card type, bank (not date/note); Esc/blur closes; fetch failures are silent.
4. **Shortcuts**: amount input accepts shorthand on blur/submit — `50k`→50000, `1tr5`→1500000, `2tr`→2000000, `1.5tr`/`1,5tr`→1500000, `1tr250`→1250000, `2m`→2000000 (m = triệu), plain digits unchanged; invalid → existing amountRequired error. Date row gets **Hôm nay / Hôm qua** chips. **Enter** submits the form (same as Lưu) except inside the note textarea and while the suggestion dropdown is open (Enter then picks the highlighted suggestion; ↑/↓ move).

**i18n (vi / en, both files, same order, asserted in resources test):** `form.moreOptions` Tuỳ chọn khác / More options · `form.payWith` Trả bằng / Pay with · `form.payWithOther` Khác / Other · `form.cashChip` Tiền mặt / Cash · `form.today` Hôm nay / Today · `form.yesterday` Hôm qua / Yesterday · `form.suggestions` Gợi ý từ giao dịch cũ / Suggestions from past transactions.

## Global Constraints
- Branch `feature/quick-entry` in both repos, cut from `feature/recurring-payments` HEAD (BE 5dcd3ff, FE 016e981).
- BE: handler `internal sealed`, explicit DI, follow existing Transactions query handlers/endpoints and integration tests. No migration.
- FE: keep `TransactionFormModal`'s public props and `TransactionFormValues` unchanged; existing TransactionFormModal / TransactionsPage / RecurringPage tests must stay green (update selectors only where the reorder requires, never weaken assertions). Split new pieces into focused files (`src/components/transactionForm/*`) — the modal is already ~1000 lines; don't grow it further than necessary.
- Gates — BE: `dotnet build DMoney.slnx` (0 warnings) && `dotnet test DMoney.slnx`; FE: `npm test && npm run build && npm run lint` (lint stays 9; `SavingsPage.test.tsx` is known-flaky under load — rerun if it alone fails). Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push; never force-push; no PRs from tasks.

## Review Focus
- Editing an existing transaction with an advance/prepaid/gold → "Tuỳ chọn khác" opens and values are intact (Task 2).
- Pay-with chip then manual change of bank → no chip shown as selected; submit sends the manual values (Task 3).
- Suggestion from an income transaction while in "Chi" → type switches to "Thu" and the category list follows (Task 4).
- `1tr5` vs `15` vs `1.500.000` pasted → 1,500,000 / 15 / 1,500,000 (Task 2).
- Enter while a Select/Combobox popover is open must not submit (Task 2).

---

### Task 1: BE — suggestions endpoint + resx
**Files:** Create `src/Application/Transactions/{GetTransactionSuggestionsQuery.cs,GetTransactionSuggestionsQueryHandler.cs,Data/TransactionSuggestionResponse.cs}`, `src/Web.Api/Endpoints/Transactions/GetTransactionSuggestions.cs`, `tests/Api.IntegrationTests/Transactions/TransactionSuggestionsEndpointTests.cs`; Modify DI, both resx, resources test.
- [ ] Failing tests: contains match case-insensitive across two plans; distinct by content keeping the latest; order by date desc; limit default 8 / max 20 (limit 50 → 20, 0 → 8); q < 2 chars → []; other user's transactions never returned; income row → type "in" with credit amount; unauthenticated → 401; resources keys.
- [ ] Implement (route literal `/transactions/suggestions` must not collide with existing routes) → gates → commit `feat: transaction suggestions endpoint` → push.

### Task 2: FE — reorder, "Tuỳ chọn khác", amount shorthand, date chips, Enter
**Files:** Modify `src/components/TransactionFormModal.tsx`; Create `src/utils/amountShorthand.ts` (+ test), `src/components/transactionForm/MoreOptionsSection.tsx`; tests in `src/components/TransactionFormModal.test.tsx`.
- [ ] Failing tests: `parseAmountShorthand` table from spec item 4 (+ invalid → null); field order (Số tiền before Nội dung before Danh mục, Trả bằng area before Ngày); more-options collapsed on create, auto-open on edit with advance/gold/prepaid; Hôm nay/Hôm qua set the date; Enter submits; Enter in note does not; Enter with an open Select doesn't.
- [ ] Implement → gates → commit `feat: quicker transaction form layout and shortcuts` → push.

### Task 3: FE — "Trả bằng" chips from Accounts
**Files:** Create `src/components/transactionForm/PayWithChips.tsx`, `src/utils/payWith.ts` (+ test); Modify `TransactionFormModal.tsx`.
- [ ] Failing tests: chip → field mapping per type; selected-state matching; Tiền mặt chip when no cash account; manual override via "Khác" clears selection; getAccounts failure → chips hidden, manual controls shown.
- [ ] Implement → gates → commit `feat: pay-with chips from accounts` → push.

### Task 4: FE — suggestions dropdown
**Files:** Modify `src/api/types.ts`, `src/api/transactionApi.ts` (`getTransactionSuggestions(q, limit?)`); Create `src/components/transactionForm/ContentSuggestions.tsx`; Modify `TransactionFormModal.tsx`.
- [ ] Failing tests (fake timers for debounce): typing ≥2 chars fetches once after 250 ms; picking fills fields (type switch for income); ↑/↓/Enter/Esc keyboard; edit mode no suggestions; fetch failure silent; < 2 chars no fetch.
- [ ] Implement → gates → commit `feat: suggestions from past transactions` → push.

### Task 5: Integration (controller)
- [ ] Whole-branch review; platform skill row; rebuild docker; PRs (or report if blocked).
