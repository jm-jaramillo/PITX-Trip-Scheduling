-- Three follow-ups from the #86 test pass, all following this app's
-- existing "no scheduled server-side execution" pattern: idempotent
-- sync functions the client calls on nav render, exactly like
-- sync_expiry_notifications() (migration 0024).
--
-- 1. expire_stale_pending_bookings() - a pending request whose date has
--    passed can never be acted on (the trip didn't happen), but it sat
--    in staff's queue forever, and staff could still "approve" a trip
--    that was already history. Auto-closes them as rejected with an
--    explicit system reason.
-- 2. sync_plate_missing_notifications() - #81 made the plate optional at
--    booking time, so an approved trip can reach its departure day with
--    no vehicle assigned. dashboard.html flags this (#83) but only if
--    the operator opens the app; this pushes it into their notification
--    panel instead.
-- 3. staff_set_booking_plate() - staff had no way to record a plate at
--    all. request_booking_change() is operator-scoped (it filters on
--    operator_id = auth.uid()), so staff at the gate couldn't enter the
--    plate for an operator who never did.

-- ---------------------------------------------------------------------------
-- 1. Auto-expire past-dated pending requests
-- ---------------------------------------------------------------------------
-- Closed as 'rejected' rather than a new 'expired' status on purpose:
-- every page in the app already renders/filters the four existing
-- statuses, and widening the CHECK constraint would mean touching all of
-- them for a state that behaves identically to rejected anyway. The
-- reason text is what distinguishes a system expiry from a staff
-- decision (decided_by stays null, which no staff rejection ever has).
create or replace function public.expire_stale_pending_bookings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.bookings set
    status           = 'rejected',
    rejection_reason = 'Automatically closed - the scheduled date passed while this request was still awaiting review.',
    decided_at       = now()
  where status = 'pending'
    and booking_date < (now() at time zone 'Asia/Manila')::date;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.expire_stale_pending_bookings() from public, anon;
grant execute on function public.expire_stale_pending_bookings() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. "Approved trip still has no plate" reminders
-- ---------------------------------------------------------------------------
-- One reminder per booking, so the dedup key is just (type, related_id)
-- - unlike the CPC/OR-CR expiry types, which repeat per validity date.
-- Partial index scoped to this type only, same approach as 0024's.
create unique index if not exists notifications_plate_missing_dedup_idx
  on public.notifications (type, related_id)
  where type = 'plate_missing';

create or replace function public.sync_plate_missing_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (
    recipient_role, recipient_id, type, title, body, link,
    related_table, related_id, related_date
  )
  select
    'operator',
    b.operator_id,
    'plate_missing',
    'Plate number still needed',
    b.route || ' on ' || b.booking_date || ' - staff already assigned '
      || coalesce(y.name, 'a bay')
      || ', but this trip has no vehicle assigned yet.',
    'dashboard.html',
    'bookings',
    b.id,
    b.booking_date
  from public.bookings b
  left join public.bays y on y.id = b.assigned_bay_id
  where b.status = 'approved'
    and b.plate_no is null
    -- Only once the trip is close enough to be actionable: from now
    -- until the end of tomorrow, Manila time. Reminding an operator
    -- about a trip three weeks out is noise, not a prompt.
    and b.booking_date
      between (now() at time zone 'Asia/Manila')::date
          and ((now() at time zone 'Asia/Manila')::date + 1)
  on conflict do nothing;
end;
$$;

revoke all on function public.sync_plate_missing_notifications() from public, anon;
grant execute on function public.sync_plate_missing_notifications() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Staff-side plate entry
-- ---------------------------------------------------------------------------
-- Deliberately narrower than request_booking_change(): sets the plate and
-- nothing else, never touches status/bay/date/slot, and can't be used to
-- assign a vehicle that isn't the booking operator's own approved,
-- route-matching one - the same eligibility rule operators are held to,
-- so "staff entered it" can't become a way around vehicle registration.
create or replace function public.staff_set_booking_plate(
  p_booking_id uuid,
  p_plate_no text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_plate text := nullif(btrim(coalesce(p_plate_no, '')), '');
begin
  if not public.is_staff() then
    raise exception 'Only staff can set a plate on an operator''s booking.';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.status not in ('pending', 'approved') then
    raise exception 'Only a pending or approved booking can have its plate set.';
  end if;

  if v_plate is not null then
    if not exists (
      select 1 from public.vehicles v
      where v.operator_id = v_booking.operator_id
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and (v.cpc_validity is null or v.cpc_validity >= current_date)
        and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
        and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(v_plate), '[^A-Z0-9]', '', 'g')
        and public.vehicle_matches_route(v.route, v_booking.route)
    ) then
      raise exception
        'That vehicle isn''t registered to this operator for % (or its CPC has expired).', v_booking.route;
    end if;

    -- Same back-to-back rule operators get (migration 0043) - a bus
    -- can't serve two adjacent 15-minute slots regardless of who typed
    -- the plate in.
    if exists (
      select 1 from public.bookings b2
      where b2.id <> p_booking_id
        and b2.operator_id = v_booking.operator_id
        and b2.status in ('pending', 'approved')
        and b2.booking_date = v_booking.booking_date
        and abs(b2.slot - v_booking.slot) = 1
        and regexp_replace(upper(b2.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(v_plate), '[^A-Z0-9]', '', 'g')
    ) then
      raise exception
        'That vehicle already has a booking in the adjacent time slot on this date.';
    end if;
  end if;

  update public.bookings set
    plate_no       = v_plate,
    last_edited_at = now()
  where id = p_booking_id;
end;
$$;

revoke all on function public.staff_set_booking_plate(uuid, text) from public, anon;
grant execute on function public.staff_set_booking_plate(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Utilization reporting source
-- ---------------------------------------------------------------------------
-- Powers the new staff Utilization page. Aggregating server-side keeps
-- the client from pulling every booking row in a date range just to
-- count them (the exact unbounded-fetch mistake #86 fixed elsewhere).
-- Returns one row per (date, gate) with approved trip counts and the
-- capacity they ran against, so the page can show occupancy as a
-- percentage without a second round trip.
create or replace function public.utilization_by_gate(
  p_from date,
  p_to date
)
returns table (
  booking_date date,
  gate text,
  trips bigint,
  cancelled bigint,
  bays_at_gate bigint,
  slot_capacity bigint
)
language sql
security definer
set search_path = public
stable
as $$
  with gates as (
    select coalesce(y.gate, 'Unassigned') as gate, count(*) as bays
    from public.bays y
    where y.is_active
    group by coalesce(y.gate, 'Unassigned')
  ),
  booked as (
    select
      b.booking_date,
      coalesce(y.gate, 'Unassigned') as gate,
      count(*) filter (where b.status = 'approved') as trips,
      count(*) filter (where b.status = 'cancelled' and b.previously_approved) as cancelled
    from public.bookings b
    left join public.bays y on y.id = b.assigned_bay_id
    where b.booking_date between p_from and p_to
      and (b.status = 'approved' or (b.status = 'cancelled' and b.previously_approved))
      and b.assigned_bay_id is not null
    group by b.booking_date, coalesce(y.gate, 'Unassigned')
  )
  select
    bk.booking_date,
    bk.gate,
    bk.trips,
    bk.cancelled,
    coalesce(g.bays, 0) as bays_at_gate,
    coalesce(g.bays, 0) * 96 as slot_capacity
  from booked bk
  left join gates g on g.gate = bk.gate
  where public.is_staff()
  order by bk.booking_date, bk.gate;
$$;

revoke all on function public.utilization_by_gate(date, date) from public, anon;
grant execute on function public.utilization_by_gate(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Unlinked-route report (data quality, from #86)
-- ---------------------------------------------------------------------------
-- ~3% of approved vehicles carry a route string that isn't one of the
-- app's canonical ROUTES (free text left over from the masterlist
-- import, or null), which makes them permanently unbookable - the
-- operator can't pick them for any trip and nothing in the UI explains
-- why. Surfaces them for staff to fix.
create or replace function public.vehicles_with_unlinked_route()
returns table (
  operator_id uuid,
  operator_name text,
  username text,
  plate_no text,
  route text,
  vehicle_id uuid
)
language sql
security definer
set search_path = public
stable
as $$
  select
    v.operator_id,
    p.operator_name,
    p.username,
    v.plate_no,
    v.route,
    v.id
  from public.vehicles v
  join public.profiles p on p.id = v.operator_id
  where v.status = 'approved'
    and (
      v.route is null
      or not exists (
        select 1 from public.route_trip_codes rc where rc.route = v.route
      )
    )
    and public.is_staff()
  order by p.operator_name, v.plate_no;
$$;

revoke all on function public.vehicles_with_unlinked_route() from public, anon;
grant execute on function public.vehicles_with_unlinked_route() to authenticated;

notify pgrst, 'reload schema';
