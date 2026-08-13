-- Switches booking time slots from hourly (0-23) to 30-minute (0-47).
--
-- `hour` is replaced by `slot`: slot N covers [N*30, N*30+30) minutes past
-- midnight, so slot 0 = 00:00-00:30, slot 1 = 00:30-01:00, ... slot 47 =
-- 23:30-00:00. Existing rows are backfilled (slot = hour * 2) before the
-- old column is dropped, so no booking data is lost in the cutover.
--
-- request_booking_change()'s signature changes (p_hour -> p_slot), so it
-- must be dropped and recreated - Postgres won't allow a parameter-list
-- change via CREATE OR REPLACE (same reason 0006 had to do this for
-- request_vehicle_change()).
--
-- Run after 0006_vehicle_fields.sql.

alter table public.bookings add column if not exists slot smallint;
update public.bookings set slot = hour * 2 where slot is null;
alter table public.bookings alter column slot set not null;
alter table public.bookings add constraint bookings_slot_range check (slot between 0 and 47);

drop index if exists bookings_date_hour_status_idx;
create index if not exists bookings_date_slot_status_idx
  on public.bookings (booking_date, slot, status);

drop index if exists bookings_unique_approved_bay_slot;
create unique index if not exists bookings_unique_approved_bay_slot
  on public.bookings (booking_date, slot, assigned_bay_id)
  where (status = 'approved' and assigned_bay_id is not null);

alter table public.bookings drop column hour;

drop function if exists public.request_booking_change(uuid, text, text, date, smallint);

create or replace function public.request_booking_change(
  p_booking_id uuid,
  p_route text,
  p_plate_no text,
  p_booking_date date,
  p_slot smallint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_was_approved boolean;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  select status into v_status
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_status is null then
    raise exception 'Booking not found.';
  end if;
  if v_status not in ('pending', 'approved') then
    raise exception
      'Only pending or approved bookings can be changed. Submit a new request instead.';
  end if;

  if coalesce(btrim(p_route), '') = '' then
    raise exception 'Route is required.';
  end if;
  if coalesce(btrim(p_plate_no), '') = '' then
    raise exception 'Plate number is required.';
  end if;
  if p_slot is null or p_slot < 0 or p_slot > 47 then
    raise exception 'Slot must be between 0 and 47.';
  end if;
  if p_booking_date is null or p_booking_date < v_today then
    raise exception 'Booking date cannot be in the past.';
  end if;

  v_was_approved := (v_status = 'approved');

  update public.bookings set
    route               = btrim(p_route),
    plate_no            = btrim(p_plate_no),
    booking_date        = p_booking_date,
    slot                = p_slot,
    status              = 'pending',
    assigned_bay_id     = null,
    rejection_reason    = null,
    decided_by          = null,
    decided_at          = null,
    previously_approved = previously_approved or v_was_approved,
    revision_count      = revision_count + 1,
    last_edited_at      = now()
  where id = p_booking_id;
end;
$$;

revoke all on function public.request_booking_change(uuid, text, text, date, smallint)
  from public, anon;
grant execute on function public.request_booking_change(uuid, text, text, date, smallint)
  to authenticated;

notify pgrst, 'reload schema';
