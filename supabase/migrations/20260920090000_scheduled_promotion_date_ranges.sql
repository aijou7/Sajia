-- Add bounded date-range schedules without breaking existing weekly promos.
-- Existing rows and the legacy 8-argument RPC remain weekly schedules.

alter table scheduled_promotions
  add column if not exists schedule_mode text not null default 'WEEKLY',
  add column if not exists start_date date,
  add column if not exists end_date date;

alter table scheduled_promotions
  drop constraint if exists scheduled_promotions_schedule_mode_check;

alter table scheduled_promotions
  add constraint scheduled_promotions_schedule_mode_check
  check (
    (schedule_mode = 'WEEKLY' and start_date is null and end_date is null)
    or (
      schedule_mode = 'DATE_RANGE'
      and start_date is not null
      and end_date is not null
      and end_date >= start_date
    )
  );

-- The new overload delegates product/outlet/price validation to the already
-- hardened weekly RPC, then applies the date-range fields in the same request.
-- Keeping the old signature means older app builds can continue saving weekly
-- promotions while the owner dashboard rolls out the new editor.
create or replace function upsert_scheduled_promotion(
  p_id text,
  p_outlet_id text,
  p_name text,
  p_start_time time,
  p_end_time time,
  p_active_days jsonb,
  p_is_active boolean,
  p_items jsonb,
  p_schedule_mode text,
  p_start_date date,
  p_end_date date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_mode text := upper(btrim(coalesce(p_schedule_mode, '')));
  normalized_days jsonb := p_active_days;
begin
  if auth.uid() is null or not current_user_has_outlet(p_outlet_id) then
    raise exception 'PROMOTION_ACCESS_DENIED';
  end if;

  if normalized_mode not in ('WEEKLY', 'DATE_RANGE') then
    raise exception 'PROMOTION_SCHEDULE_MODE_INVALID';
  end if;

  if normalized_mode = 'DATE_RANGE' then
    if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
      raise exception 'PROMOTION_DATE_RANGE_INVALID';
    end if;
    -- A date-range promo runs every day in the selected inclusive range.
    normalized_days := '[1, 2, 3, 4, 5, 6, 7]'::jsonb;
  else
    if p_start_date is not null or p_end_date is not null then
      raise exception 'PROMOTION_DATE_RANGE_INVALID';
    end if;
  end if;

  perform upsert_scheduled_promotion(
    p_id,
    p_outlet_id,
    p_name,
    p_start_time,
    p_end_time,
    normalized_days,
    p_is_active,
    p_items
  );

  update scheduled_promotions
  set schedule_mode = normalized_mode,
      start_date = case when normalized_mode = 'DATE_RANGE' then p_start_date else null end,
      end_date = case when normalized_mode = 'DATE_RANGE' then p_end_date else null end,
      updated_at = now()
  where id = p_id
    and outlet_id = p_outlet_id;

  if not found then
    raise exception 'PROMOTION_NOT_FOUND';
  end if;
  return p_id;
end;
$$;

revoke all on function upsert_scheduled_promotion(
  text, text, text, time, time, jsonb, boolean, jsonb, text, date, date
) from public, anon;
grant execute on function upsert_scheduled_promotion(
  text, text, text, time, time, jsonb, boolean, jsonb, text, date, date
) to authenticated;
