# Local account and financial-data safety

## Incident addressed

Email logout previously removed the owner binding while retaining the encrypted
database. On the next OTP login, onboarding treated the remaining records as
unowned legacy data and cleared them, including unsynced sales. Background sync
and PIN recovery also interpreted a changed remote outlet scope as permission to
delete local records.

## Invariants

- Logout removes the usable authentication session, not local data ownership.
- Same-owner login preserves local transactions, their pending flags, and the
  selected outlet when it still belongs to the account.
- A different owner cannot access or upload the existing owner's data. Account
  switching with nonempty local data stops with an actionable error; it never
  purges records automatically.
- Legacy installations with a missing binding may be reclaimed only when the
  authenticated owner-outlet RPC proves all local outlet IDs. Queue-only data and
  orphaned financial records must not be mistaken for an empty installation.
  Unattributable legacy records require a backup and explicit investigation.
- Remote outlet mismatch or ownership lookup failure stops the sync worker before
  uploads. A mismatch is not an instruction to delete data.
- Login/logout pauses and drains the current sync worker before changing the
  Supabase session. A timeout aborts the account change.
- Cloud pulls check pending financial rows and apply snapshots in a single local
  database transaction. Pending records are never replaced by old cloud copies.
- Upload acknowledgement marks a financial row synced only if the local snapshot
  still matches what was uploaded. Concurrent edits remain pending for retry.
- Cloud expiry, upload failure, and partially eligible branches keep local sales
  durable and show a pending/failed status, not complete success.

`retainOnlyOutlets` and `clearBusinessData` remain destructive maintenance APIs.
They have no automatic authentication or sync callers. Do not reuse them for an
account change without explicit authorization to remove local data.

## Compatibility and release

No database schema, Supabase migration, server API, package ID, encryption key, or
serialization contract changes are required. Existing mobile versions still
contain the unsafe paths until updated. The owner web dashboard cannot recreate
sales absent from both the device database and Cloud.

Preserve the affected device before investigating recovery: do not uninstall,
clear application data, restore over its database, or invent replacement sales.
This patch prevents recurrence; it does not recover previously deleted rows.

Prefer a forward fix over downgrading to the unsafe logout code. If a release is
withdrawn, preserve the encrypted database, device key, and owner binding; do not
use a data reset as rollback.

## Verification

Regression coverage: `local_account_preservation_test.dart`,
`sync_account_preservation_test.dart`, and `sync_status_feedback_test.dart`.
The sync tests use a disposable in-memory database and mocked authenticated Cloud
responses, including 11 sales totaling Rp331,420. They do not access production.

Check Android installation/runtime independently before describing the APK as
verified. Flutter unit/widget tests and an owner web build are not substitutes
for a device check.

Local validation on 2026-10-08: source analysis reported no issues; the full
Flutter suite passed 138 tests. The pending-sync dialog was rendered and reviewed
at 390x844 with enlarged text and 800x600. Settings sync feedback, retry, and
confirmed email logout were exercised in widget tests.

NOT VERIFIED — Android APK build and physical-device runtime: no Android SDK or
tablet connection is available locally. iOS build/runtime also requires a macOS
build environment and remains unverified. No production deployment, APK release,
database recovery, or production data mutation was performed for this patch.
