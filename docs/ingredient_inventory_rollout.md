# Ingredient inventory rollout

## Deployment order

1. Back up the production database before rollout. Existing owner costing migrations (20260925100000 and 20260926100000) must already be installed.
2. Apply `20261007100000_owner_menu_deletion.sql`, then `20261007110000_ingredient_inventory.sql`.
   For **Bahan habis**, apply the additive `20261007130000_ingredient_depletion.sql` before deploying the new owner bundle.
   For **Koreksi harga**, also apply `20261009100000_ingredient_purchase_price_corrections.sql` before the owner bundle. The new dashboard still reads purchases on the old schema but disables correction with a migration notice.
3. Deploy the owner dashboard and updated Android app. The shared costing RPC signature remains compatible with older clients. Older APKs also consume linked ingredients when paid order items reach the server.
4. Verify with the real owner session and the correct outlet before publishing an APK update.

No production migration is run by `scripts/verify_ingredient_inventory.cjs`. It uses a disposable PostgreSQL/WASM database and simplified authentication fixtures; it is not proof of production RLS or multi-session concurrency behavior.

## Owner workflow

- **Bahan & Belanja → Tambah bahan:** enter a reusable name and base stock unit (g/ml/pcs).
- **Catat belanja:** pick ingredients, enter quantities (including kg/liter) and total purchase prices. Purchases increase stock and appear in the purchase report, not operating expenses.
- **Laporan belanja → Koreksi harga:** correct each ingredient's total price, not its quantity/unit. Example: 3 L milk at Rp22,000/L must have a **Rp66,000 total**, not Rp22,000. A per-unit preview helps check the entry. The report keeps the original purchase date and shows the corrected total, with the initial total retained. No new purchase, stock movement, sale or expense is created.
- Price corrections append owner-attributed revisions; the original receipt and retry fingerprint remain intact. Current average inventory costs are recalculated from movements in **recording order** using the latest purchase prices, including later purchases and intervening consumption. A zero/negative balance before a later purchase resets the average, just like the original purchase calculation. A ledger/balance mismatch aborts the correction rather than guessing. Future recipe HPP is refreshed; historical sale HPP, usage/depletion expenses and recipe versions are **not rewritten**. This is not retrospective financial restatement.
- A stale price revision requires closing/reopening the dialog. A lost-response retry sends the same frozen correction ID/payload and returns its existing result, even after another revision. Closing the dialog reloads reports so an uncertain response is not left displayed as the old price. Quantity/date/unit correction and undoing a purchase are not included.
- **Menu → Resep:** select catalog ingredients and per-portion quantities. Average purchase costs determine recipe HPP. Manual recipe lines remain supported but cannot consume tracked ingredients.
- Paid sales consume the recipe effective at checkout time after sync. Voids restore the original quantities once. No stock is deducted retroactively for sales before a linked recipe existed.
- **Pakai sendiri / R&D:** no payment and no revenue. Ingredients are consumed and one HPP expense is recorded. The expense cannot be edited/deleted separately from the usage receipt. Correction/reversal of internal usage is not implemented in this release.
- **Catat pemakaian → Keperluan → Penjualan sebelumnya:** choose the menu, portion count and sale date for sales whose ingredients were never tracked. Uses the current linked recipe, including when the sale predates that recipe. Only ingredient stock is adjusted; no order, revenue, additional expense or finished-product stock deduction is created. A menu with no linked ingredients is rejected. Partial/manual recipe lines remain explicitly marked untracked. Owners must confirm all devices have synced and these portions were not already deducted. Manual aggregate input cannot automatically identify duplicate historic transactions; do not enter them again with a new receipt.
- **Stok bahan → Bahan habis:** confirm physical zero after all cashier devices have synced. Choose **Penjualan sebelum tracking** for old purchases already consumed by sales (no extra expense), or **Pakai sendiri / Terbuang / selisih stok** to charge the remaining stock at its current average cost as one operating expense. Both create an immutable receipt and inventory movement; historical sales/HPP are not rewritten. This is a manual zero confirmation, not an automatic reconstruction of past recipes or sales.
- A changed stock/price while the confirmation dialog is open rejects the request and requires a reload. An uncertain response retries the same receipt without consuming a later purchase. Zero/negative stock cannot be cleared again. The system cannot inspect the outbox of a disconnected tablet; synchronize every device before confirming zero.
- These owner-web changes do not require an APK update. Existing Android sync retains the old internal-use RPC and cannot directly create a historical stock correction. Expense protection also covers depletion receipts on the server; old app delete controls may still be visible but such deletes are rejected safely.
- Buffer allowances are estimates for unmeasured costs. Do not also include separately recorded R&D costs in the buffer.

## Important behavior

- New ingredients start at zero stock/cost. Record opening purchases before selecting them in recipes.
- Negative ingredient stock is shown explicitly; offline sales are not silently discarded or clamped. Reconcile missing purchases or actual consumption.
- Purchase valuation uses a moving weighted average at recording time. Backdated purchase reports do not reprice previous paid transactions.
- Tablet menu changes refresh in the open owner Menu tab every 30 seconds. Refresh pauses during dialogs/background views; a failed refresh retains the last displayed data.
- Internal usage remains pending even after five failed uploads, with a stable request ID. The sync indicator reports failure rather than claiming success.
- Deleted menu/category IDs have tombstones; stale device uploads cannot recreate them. Order item snapshots and recipe history remain available.

## Verification before release

- `flutter analyze`, `flutter test --dart-define=KASATA_VISUAL_REVIEW=true`, owner web release build.
- `scripts/verify_ingredient_inventory.cjs` with `@electric-sql/pglite@0.5.8` available through `NODE_PATH`.
- Purchase correction suite: 3 L / Rp22k → Rp66k, weighted later purchases, backdated recording order, zero/negative stock, immutable historical sale/expense snapshots, multi-line atomicity, stale revisions, ID conflicts, retry after later revisions, owner/Cloud grants and simplified-fixture RLS, migration replay. Actual production authentication and multi-session contention remain **NOT VERIFIED** by the disposable single-database runner.
- Real owner: purchase 1 kg, link 18 g recipe, sell two portions, retry sync, void, consume one R&D portion. Verify one deduction/reversal/expense, correct outlet visibility, and no R&D order/payment.
- Android device: owner discount sheet, no-payment confirmation, offline/resume, sync acknowledgment. iOS requires its own build/runtime environment.

## Recovery

Keep additive inventory tables and receipts if reverting clients; do not drop the ledger or remove triggers after transactions have consumed inventory. Revert the UI/app artifact while preserving database protections, then investigate the failed request using its stable ID. A database rollback after live writes requires a reviewed reconciliation plan, not blind migration reversal.

## Price-correction verification (2026-10-09)

Local verification: 197 Flutter tests passed; analyzer reported no issues; owner web release build and Wasm dry run succeeded. Correction dialogs were rendered and visually inspected at 390 px and 1280 px; the keyboard-open narrow layout and save/retry/conflict controls were exercised by widget tests. Disposable SQL suites and migration replay passed. Production migration, real owner-session runtime and multi-session database contention are **NOT VERIFIED — no production rollout was performed**. This owner-only feature needs no APK update; no Android/iOS build or device runtime was performed for this change.

## Production database installation (2026-10-10)

The price-correction migration was installed through Supabase SQL Editor inside an explicit transaction after checking prerequisites and confirming zero ingredient ledger mismatches. Post-install checks confirmed the correction table/RPC, authenticated-only execution, private valuation helper, and no direct authenticated audit updates. Existing data counts remained 12 ingredients, 12 purchases and 49 stock movements; the correction audit contained zero entries. No customer purchase was repriced during deployment.

The scoped release checkout passed 148 Flutter tests, analyzer, disposable SQL suites/migration replay, and owner web release build with a successful Wasm dry run. Shared OTP code was separated from the native-only local-account guard extension to avoid importing SQLite FFI into the web bundle; guard behavior and call sites remain unchanged. Unrelated pending hardening changes were excluded. Actual owner-session saving, production multi-session contention and Android/iOS build/device runtime remain **NOT VERIFIED**; an APK update is not part of this owner-web rollout.
