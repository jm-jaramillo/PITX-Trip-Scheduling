-- Lets an operator hand off an already-booked slot to another operator
-- (e.g. they can't make it and have an internal arrangement with another
-- company to cover it). Needs PITX staff approval; once approved, the
-- schedule shows the previous operator struck through next to the new one.
--
-- The receiving operator has no in-app acceptance step - this models the
-- "internal agreement" as already having happened between the two
-- companies, with PITX staff as the actual gate before it takes effect.
--
-- Run after 0009_four_hour_lockout.sql.

alter table public.bookings
  add column if not exists previous_operator_name text;

comment on column public.bookings.previous_operator_name is
  'Set when a transfer is approved: the operator name this booking had
   immediately before the handoff, shown struck through next to the new
   operator on the schedule.';

create table if not exists public.booking_transfers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  from_operator_id uuid not null references public.profiles (id),
  to_operator_id uuid not null references public.profiles (id),
  to_username text not null,
  new_plate_no text not null,
  reason text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);

create index if not exists booking_transfers_status_idx on public.booking_transfers (status);
create index if not exists booking_transfers_booking_id_idx on public.booking_transfers (booking_id);

alter table public.booking_transfers enable row level security;

-- Both sides of the handoff can see their own transfer requests; staff see
-- everything. No direct INSERT/UPDATE policy for anyone - creating and
-- deciding a transfer both go through the SECURITY DEFINER functions
-- below, which do their own authorization checks; that's what makes the
-- from_operator_id/to_operator_id/status transitions trustworthy rather
-- than something any authenticated user could write directly.
drop policy if exists booking_transfers_select on public.booking_transfers;
create policy booking_transfers_select on public.booking_transfers
  for select
  using (
    from_operator_id = auth.uid()
    or to_operator_id = auth.uid()
    or public.is_staff()
  );

-- ---------------------------------------------------------------------------
-- request_booking_transfer: the operator who currently holds the booking
-- proposes handing it to another operator, identified by username (there's
-- no cross-operator directory in the UI - the two companies already know
-- each other from their own arrangement, so a username is enough to
-- resolve the account without exposing the wider profiles table).
-- ---------------------------------------------------------------------------
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
  -- Same lead-time rule as editing a booking (migration 0009) - a handoff
  -- is still a change to an active booking.
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
    booking_id, from_operator_id, to_operator_id, to_username, new_plate_no, reason
  ) values (
    p_booking_id, auth.uid(), v_to_profile.id, v_to_profile.username,
    btrim(p_new_plate_no), nullif(btrim(coalesce(p_reason, '')), '')
  );
end;
$$;

revoke all on function public.request_booking_transfer(uuid, text, text, text) from public, anon;
grant execute on function public.request_booking_transfer(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- approve_booking_transfer / reject_booking_transfer: staff-only. Checked
-- with is_staff() explicitly inside the function body - being SECURITY
-- DEFINER means these bypass RLS entirely, so without this check any
-- authenticated user could call them to approve their own transfer.
-- ---------------------------------------------------------------------------
create or replace function public.approve_booking_transfer(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.booking_transfers%rowtype;
  v_booking public.bookings%rowtype;
  v_to_name text;
begin
  if not public.is_staff() then
    raise exception 'Only PITX staff can decide on transfers.';
  end if;

  select * into v_transfer
  from public.booking_transfers
  where id = p_transfer_id and status = 'pending'
  for update;

  if v_transfer.id is null then
    raise exception 'Transfer request not found or already decided.';
  end if;

  select * into v_booking from public.bookings where id = v_transfer.booking_id for update;
  if v_booking.id is null then
    raise exception 'The original booking no longer exists.';
  end if;

  select coalesce(operator_name, username) into v_to_name
  from public.profiles where id = v_transfer.to_operator_id;

  update public.bookings set
    previous_operator_name = v_booking.operator_name,
    operator_id = v_transfer.to_operator_id,
    operator_name = coalesce(v_to_name, v_booking.operator_name),
    plate_no = v_transfer.new_plate_no
  where id = v_booking.id;

  update public.booking_transfers set
    status = 'approved',
    decided_by = auth.uid(),
    decided_at = now()
  where id = p_transfer_id;
end;
$$;

revoke all on function public.approve_booking_transfer(uuid) from public, anon;
grant execute on function public.approve_booking_transfer(uuid) to authenticated;

create or replace function public.reject_booking_transfer(p_transfer_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Only PITX staff can decide on transfers.';
  end if;

  update public.booking_transfers set
    status = 'rejected',
    rejection_reason = nullif(btrim(coalesce(p_reason, '')), ''),
    decided_by = auth.uid(),
    decided_at = now()
  where id = p_transfer_id and status = 'pending';

  if not found then
    raise exception 'Transfer request not found or already decided.';
  end if;
end;
$$;

revoke all on function public.reject_booking_transfer(uuid, text) from public, anon;
grant execute on function public.reject_booking_transfer(uuid, text) to authenticated;

notify pgrst, 'reload schema';
