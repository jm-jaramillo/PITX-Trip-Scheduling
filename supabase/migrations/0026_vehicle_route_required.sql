-- Operators can now only book a slot using a vehicle that's actually
-- registered for that route (previously #48 only suggested this via a
-- grouped dropdown - not enforced). RLS is the real gate here, same as
-- everywhere else in this app - the client-side dropdown filter
-- (dashboard.html) is UX only and never the actual protection.
--
-- Matching mirrors dashboard.html's own vehicleMatchesRoute() exactly
-- (significant word overlap between the vehicle's free-text `route` and
-- the canonical booking route, ignoring generic filler words) - a SQL
-- port of the same function, not a different, possibly-diverging rule.
--
-- Run after 0025_vehicle_pending_notify_on_edit.sql.

create or replace function public.route_tokens(p text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    array_agg(w) filter (
      where length(w) >= 3
        and w not in ('CITY', 'VIA', 'THE', 'AND', 'OF', 'TUNNEL')
    ),
    array[]::text[]
  )
  from unnest(
    regexp_split_to_array(
      upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', ' ', 'g')),
      '\s+'
    )
  ) as w
  where w <> '';
$$;

comment on function public.route_tokens(text) is
  'Significant words in a route string, filler words dropped - SQL port '
  'of dashboard.html''s routeTokens(), kept in lockstep with it.';

create or replace function public.vehicle_matches_route(p_vehicle_route text, p_booking_route text)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from unnest(public.route_tokens(p_booking_route)) as bt
    where bt = any(public.route_tokens(p_vehicle_route))
  );
$$;

comment on function public.vehicle_matches_route(text, text) is
  'SQL port of dashboard.html''s vehicleMatchesRoute() - true if the '
  'vehicle''s own free-text route shares a significant word with the '
  'canonical booking route.';

-- New bookings: the plate must belong to one of the operator's own
-- approved, LTFRB-eligible vehicles whose route matches the one being
-- booked - same eligibility rule the plate dropdown itself already
-- applies (see dashboard.html's loadApprovedVehicles).
drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (
    operator_id = auth.uid()
    and status = 'pending'
    and public.slot_start_at(booking_date, slot) >= now() + interval '4 hours'
    and exists (
      select 1 from public.vehicles v
      where v.operator_id = auth.uid()
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(plate_no), '[^A-Z0-9]', '', 'g')
        and public.vehicle_matches_route(v.route, route)
    )
  );

-- request_booking_change(): same rule, since an edit can change the
-- route/plate combination too. Signature unchanged from 0009, so
-- CREATE OR REPLACE is fine.
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
  v_booking public.bookings%rowtype;
  v_was_approved boolean;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  select * into v_booking
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.status not in ('pending', 'approved') then
    raise exception
      'Only pending or approved bookings can be changed. Submit a new request instead.';
  end if;

  if public.slot_start_at(v_booking.booking_date, v_booking.slot) < now() + interval '4 hours' then
    raise exception
      'This booking starts within 4 hours and can no longer be changed.';
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
  if public.slot_start_at(p_booking_date, p_slot) < now() + interval '4 hours' then
    raise exception 'Please choose a time at least 4 hours from now.';
  end if;

  if not exists (
    select 1 from public.vehicles v
    where v.operator_id = auth.uid()
      and v.status = 'approved'
      and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
      and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
        = regexp_replace(upper(p_plate_no), '[^A-Z0-9]', '', 'g')
      and public.vehicle_matches_route(v.route, p_route)
  ) then
    raise exception
      'That vehicle isn''t registered for this route. Choose a vehicle registered for %, or pick a different route.', p_route;
  end if;

  v_was_approved := (v_booking.status = 'approved');

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

notify pgrst, 'reload schema';
