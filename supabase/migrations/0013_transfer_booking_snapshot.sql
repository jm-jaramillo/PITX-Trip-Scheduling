-- The receiving operator needs to see what they're being asked to confirm
-- (date, slot, route) before they've accepted - but bookings RLS only lets
-- an operator read their *own* bookings, and this booking isn't theirs
-- yet. Rather than widening bookings RLS to cover this one case, snapshot
-- the relevant fields onto booking_transfers at request time, which the
-- requester (the booking's current owner) can already read.
--
-- Run after 0012_transfer_recipient_confirmation.sql.

alter table public.booking_transfers
  add column if not exists booking_date date,
  add column if not exists slot smallint,
  add column if not exists route text,
  add column if not exists previous_plate_no text;

-- Backfill existing rows from their (still-readable-by-staff) booking.
update public.booking_transfers bt
set booking_date = b.booking_date, slot = b.slot, route = b.route,
    previous_plate_no = b.plate_no
from public.bookings b
where b.id = bt.booking_id and bt.booking_date is null;

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

  insert into public.booking_transfers (
    booking_id, from_operator_id, to_operator_id, to_username, new_plate_no, reason,
    booking_date, slot, route, previous_plate_no
  ) values (
    p_booking_id, auth.uid(), v_to_profile.id, v_to_profile.username,
    btrim(p_new_plate_no), nullif(btrim(coalesce(p_reason, '')), ''),
    v_booking.booking_date, v_booking.slot, v_booking.route, v_booking.plate_no
  );
end;
$$;

revoke all on function public.request_booking_transfer(uuid, text, text, text) from public, anon;
grant execute on function public.request_booking_transfer(uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
