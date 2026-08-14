-- Lets the transfer dialog offer a dropdown of the *receiving* operator's
-- approved vehicles for "their plate no." instead of free text - the
-- sending operator can't query another operator's vehicles directly
-- (vehicles RLS only allows reading your own), so this is a narrow
-- read-only lookup, same pattern as list_operator_accounts() (migration
-- 0011).
--
-- Run after 0015_vehicle_or_cr_numbers.sql.

create or replace function public.list_operator_vehicles(p_username text)
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
  order by v.plate_no;
$$;

revoke all on function public.list_operator_vehicles(text) from public, anon;
grant execute on function public.list_operator_vehicles(text) to authenticated;

-- request_booking_transfer() now validates the new plate against the
-- receiving operator's own approved vehicles, same rule the booking form
-- itself already enforces for the requesting operator.
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
  ) then
    raise exception 'That plate isn''t one of the receiving operator''s approved vehicles.';
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
