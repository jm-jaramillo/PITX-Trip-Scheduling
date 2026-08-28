-- Widens booking slots from 30-minute to 15-minute granularity - slot N
-- now covers [N*15, N*15+15) minutes past midnight instead of
-- [N*30, N*30+30), so a day is 96 slots (0-95) instead of 48 (0-47).
-- Matches the client-side change to SLOTS/formatSlot/slotStartMillis
-- in docs/assets/app.js (must stay in lockstep - see those comments).
--
-- IMPORTANT - existing data: if this runs against a database that
-- already has booking rows, their `slot` values were written under the
-- OLD (30-minute) scheme and would silently point at the wrong wall-
-- clock time once every function below starts reading slot as a
-- 15-minute index (old slot N started at N*30 minutes; under the new
-- scheme that same wall-clock instant is at slot N*2). The UPDATE
-- below re-maps every existing row so its slot keeps meaning the same
-- real time - safe to run even on a table that turns out to be empty
-- (a genuinely fresh database), since it's a no-op there.
--
-- Per the operator's own instruction this migration is NOT applied to
-- the current live database - it's prepared ahead of a planned
-- clean-slate database upload (see #76's note). Apply it there with
-- scripts/run-migration.mjs once that database is live, then verify
-- the booking form's actual submit path end to end (client and server
-- slot math must never disagree even for a moment - running this
-- migration and deploying the new docs/assets/app.js together is not
-- optional).
--
-- Run after 0037_operator_profile_redesign.sql.

update public.bookings set slot = slot * 2 where slot is not null;

alter table public.bookings
  drop constraint if exists bookings_slot_range;
alter table public.bookings
  add constraint bookings_slot_range check (slot between 0 and 95);

-- slot_start_at: same signature, just the interval per slot changes -
-- CREATE OR REPLACE is fine.
create or replace function public.slot_start_at(p_booking_date date, p_slot smallint)
returns timestamptz
language sql
immutable
as $$
  select (p_booking_date::timestamp + (p_slot * interval '15 minutes'))
    at time zone 'Asia/Manila';
$$;

-- compute_trip_number: same signature, same shape - only the
-- slot-to-clock-time math (v_hour/v_minute) changes from a 30-minute
-- step to a 15-minute one. A trip number describes the route and the
-- slot's start time, so this is the only part of it slot width affects.
create or replace function public.compute_trip_number(
  p_route text, p_slot smallint, p_booking_date date, p_exclude_booking_id uuid
)
returns text
language plpgsql
stable
as $$
declare
  v_code text;
  v_hour int;
  v_minute int;
  v_base text;
  v_suffix_count int;
begin
  select code into v_code from public.route_trip_codes where route = p_route;
  if v_code is null then
    v_code := rpad(
      upper(regexp_replace(coalesce(p_route, ''), '[^A-Za-z]', '', 'g')),
      3, 'X'
    );
    v_code := left(v_code, 3);
  end if;

  v_hour := (p_slot * 15) / 60;
  v_minute := (p_slot * 15) % 60;
  v_base := v_code || lpad(v_hour::text, 2, '0') || lpad(v_minute::text, 2, '0');

  select count(*) into v_suffix_count
  from public.bookings
  where booking_date = p_booking_date
    and route = p_route
    and slot = p_slot
    and status = 'approved'
    and trip_number is not null
    and id <> p_exclude_booking_id;

  return v_base || case when v_suffix_count = 0 then '' else chr(64 + v_suffix_count) end;
end;
$$;

notify pgrst, 'reload schema';
