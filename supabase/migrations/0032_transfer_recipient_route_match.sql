-- The transfer dialog let a sender pick *any* other operator account and
-- *any* of that operator's approved vehicles, with no route check at
-- all - a booking for "Tabaco City, Albay" could be handed to an
-- operator (and a specific vehicle) with nothing to do with that route.
-- Restrict both steps to the booking's own route, the same "must be
-- registered for the route it books" rule #51/#60 already enforce for
-- the original operator:
--
--   1. list_operator_accounts() now takes the booking's route and only
--      returns operators who have a matching approved vehicle - no point
--      offering an operator who could never receive this booking anyway.
--   2. list_operator_vehicles() now takes the same route and only
--      returns that operator's vehicles registered for it.
--   3. request_booking_transfer() now re-validates the route match
--      server-side (the client-side dropdowns above are UX only, same
--      as everywhere else in this app) - the real gate.
--
-- Matching reuses vehicle_matches_route() (#60's plain-equality
-- restart), not a separate rule - one source of truth for "is this
-- vehicle registered for this route" everywhere it's checked.
--
-- Both list_* functions change their parameter list, so they're
-- DROP + CREATE, not CREATE OR REPLACE.
--
-- Run after 0031_vehicle_matches_route_exact.sql.

drop function if exists public.list_operator_accounts();

create function public.list_operator_accounts(p_route text)
returns table (username text, operator_name text)
language sql
security definer
set search_path = public
stable
as $$
  select p.username, p.operator_name
  from public.profiles p
  where p.role = 'operator'
    and p.id <> auth.uid()
    and exists (
      select 1 from public.vehicles v
      where v.operator_id = p.id
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and public.vehicle_matches_route(v.route, p_route)
    )
  order by coalesce(p.operator_name, p.username);
$$;

comment on function public.list_operator_accounts(text) is
  'Operator accounts (excluding the caller) with at least one approved, '
  'LTFRB-eligible vehicle registered for the given route - only '
  'operators who could actually receive a transfer for that route.';

revoke all on function public.list_operator_accounts(text) from public, anon;
grant execute on function public.list_operator_accounts(text) to authenticated;

drop function if exists public.list_operator_vehicles(text);

create function public.list_operator_vehicles(p_username text, p_route text)
returns table (plate_no text, bus_number text)
language sql
security definer
set search_path = public
stable
as $$
  select v.plate_no, v.bus_number
  from public.vehicles v
  join public.profiles p on p.id = v.operator_id
  where lower(p.username) = lower(btrim(p_username))
    and p.role = 'operator'
    and v.status = 'approved'
    and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
    and public.vehicle_matches_route(v.route, p_route)
  order by v.plate_no;
$$;

comment on function public.list_operator_vehicles(text, text) is
  'A specific operator''s approved, LTFRB-eligible vehicles registered '
  'for the given route - feeds the transfer dialog''s plate dropdown, '
  'narrowed the same way the booking form narrows the requesting '
  'operator''s own plate options.';

revoke all on function public.list_operator_vehicles(text, text) from public, anon;
grant execute on function public.list_operator_vehicles(text, text) to authenticated;

-- request_booking_transfer() now re-checks the route match itself,
-- rather than only checking the plate is *an* approved vehicle of the
-- receiving operator - the actual enforcement, since the dropdowns above
-- are UX only.
create or replace function public.request_booking_transfer(
  p_booking_id uuid,
  p_to_username text,
  p_new_plate_no text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_to_profile public.profiles%rowtype;
  v_from_name text;
begin
  select * into v_booking
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.status not in ('pending', 'approved') then
    raise exception 'Only pending or approved bookings can be transferred.';
  end if;
  if public.slot_start_at(v_booking.booking_date, v_booking.slot) < now() + interval '4 hours' then
    raise exception 'This booking starts within 4 hours and can no longer be transferred.';
  end if;
  if exists (
    select 1 from public.booking_transfers
    where booking_id = p_booking_id and status = 'pending'
  ) then
    raise exception 'A transfer for this booking is already awaiting review.';
  end if;

  if coalesce(btrim(p_to_username), '') = '' then
    raise exception 'The receiving operator''s username is required.';
  end if;
  if coalesce(btrim(p_new_plate_no), '') = '' then
    raise exception 'Plate number is required.';
  end if;

  select * into v_to_profile
  from public.profiles
  where lower(username) = lower(btrim(p_to_username)) and role = 'operator';

  if v_to_profile.id is null then
    raise exception 'No operator account found with that username.';
  end if;
  if v_to_profile.id = auth.uid() then
    raise exception 'You can''t transfer a booking to yourself.';
  end if;

  if not exists (
    select 1 from public.vehicles
    where operator_id = v_to_profile.id
      and status = 'approved'
      and lower(plate_no) = lower(btrim(p_new_plate_no))
      and public.vehicle_matches_route(route, v_booking.route)
  ) then
    raise exception 'That plate isn''t one of the receiving operator''s approved vehicles registered for this booking''s route.';
  end if;

  select coalesce(operator_name, username) into v_from_name
  from public.profiles where id = auth.uid();

  insert into public.booking_transfers (
    booking_id, from_operator_id, to_operator_id, to_username, new_plate_no, reason,
    booking_date, slot, route, previous_plate_no, from_operator_name
  ) values (
    p_booking_id, auth.uid(), v_to_profile.id, v_to_profile.username,
    btrim(p_new_plate_no), nullif(btrim(coalesce(p_reason, '')), ''),
    v_booking.booking_date, v_booking.slot, v_booking.route, v_booking.plate_no, v_from_name
  );
end;
$$;

revoke all on function public.request_booking_transfer(uuid, text, text, text) from public, anon;
grant execute on function public.request_booking_transfer(uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
