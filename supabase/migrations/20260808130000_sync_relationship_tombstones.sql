-- Propagate recovery-data deletions across devices.
--
-- Tables and staff/outlet assignments are available as account recovery data
-- even without Cloud. Their deletions therefore need the same durable,
-- owner-scoped tombstones already used by products and expenses.

alter table public.sync_tombstones
  drop constraint if exists sync_tombstones_entity_type_check;

alter table public.sync_tombstones
  add constraint sync_tombstones_entity_type_check
  check (
    entity_type in (
      'product',
      'expense',
      'restaurant_table',
      'user_outlet_access'
    )
  );

-- The existing owner_scope_sync_tombstones FOR ALL policy still enforces
-- current_user_has_outlet(outlet_id). DELETE is granted solely so an owner can
-- intentionally restore a newer user/outlet assignment that supersedes an
-- older tombstone with the same deterministic record id.
grant delete on table public.sync_tombstones to authenticated;
