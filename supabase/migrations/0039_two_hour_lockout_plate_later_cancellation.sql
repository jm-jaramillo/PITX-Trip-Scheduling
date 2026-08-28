-- Three independent changes, bundled together because they all touch
-- bookings/request_booking_change() and are easiest to reason about as
-- one pass over that function:
--
-- 1. Lead time for booking/changing a slot: 4 hours -> 2 hours.
-- 2. plate_no becomes optional at booking time - operators now book a
--    destination + time slot only; the plate is filled in later (any
--    time up to and including the day of the trip) via
--    request_booking_change(), which no longer treats a plate-only
--    change as material (it used to reset ANY change back to
--    'pending' and re-run the lead-time check, which would have
--    blocked exactly the "fill it in on the day" workflow this adds).
-- 3. Cancelling a booking now requires staff approval, for both
--    pending and approved bookings - the old bookings_cancel_own
--    policy let an operator instantly cancel their own pending
--    request with no review at all; that's dropped in favor of a
--    request/approve/decline flow, matching how every other write to
--    an approved booking already works in this app.
--
-- Also fixes a stale bug noticed while touching this function:
-- request_booking_change() still checked p_slot against the old
-- 0-47 (30-minute) range; slots have been 0-95 since migration 0038.

-- ---------------------------------------------------------------------------
-- 1 & 2: plate_no optional, insert policy relaxed to match
-- ---------------------------------------------------------------------------
alter table public.bookings
  alter column plate_no drop not null;

drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (
    operator_id = auth.uid()
    and status = 'pending'
    and public.slot_start_at(booking_date, slot) >= now() + interval '2 hours'
    and (
      plate_no is null
      or exists (
        select 1 from public.vehicles v
        where v.operator_id = auth.uid()
          and v.status = 'approved'
          and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
          and (v.cpc_validity is null or v.cpc_validity >= current_date)
          and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
          and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
            = regexp_replace(upper(bookings.plate_no), '[^A-Z0-9]', '', 'g')
          and public.vehicle_matches_route(v.route, bookings.route)
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 3: cancellation request/approve/decline
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists cancellation_requested_at timestamptz,
  add column if not exists cancellation_reason text;

comment on column public.bookings.cancellation_requested_at is
  'Set when the operator asks to cancel this booking; cleared on decline. '
  'Cancelling still requires staff approval (see approve_booking_cancellation) '
  '- this column only marks the request as pending, it never cancels the '
  'booking by itself.';

-- Operators may no longer cancel their own booking directly - superseded
-- by the request/approve flow below.
drop policy if exists bookings_cancel_own on public.bookings;

create or replace function public.request_booking_cancellation(
  p_booking_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  select * into v_booking
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.status not in ('pending', 'approved') then
    raise exception 'Only pending or approved bookings can be cancelled.';
  end if;
  if v_booking.cancellation_requested_at is not null then
    raise exception 'A cancellation request is already pending for this booking.';
  end if;

  update public.bookings set
    cancellation_requested_at = now(),
    cancellation_reason       = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_booking_id;
end;
$$;

create or replace function public.cancel_booking_cancellation_request(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  select * into v_booking
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.cancellation_requested_at is null then
    raise exception 'This booking has no pending cancellation request.';
  end if;

  update public.bookings set
    cancellation_requested_at = null,
    cancellation_reason       = null
  where id = p_booking_id;
end;
$$;

create or replace function public.approve_booking_cancellation(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if not public.is_staff() then
    raise exception 'Only staff can approve a cancellation.';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.cancellation_requested_at is null then
    raise exception 'This booking has no pending cancellation request.';
  end if;

  update public.bookings set
    status          = 'cancelled',
    assigned_bay_id = null,
    decided_by      = auth.uid(),
    decided_at      = now()
  where id = p_booking_id;
end;
$$;

create or replace function public.decline_booking_cancellation(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if not public.is_staff() then
    raise exception 'Only staff can decline a cancellation.';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if v_booking.id is null then
    raise exception 'Booking not found.';
  end if;
  if v_booking.cancellation_requested_at is null then
    raise exception 'This booking has no pending cancellation request.';
  end if;

  update public.bookings set
    cancellation_requested_at = null,
    cancellation_reason       = null
  where id = p_booking_id;
end;
$$;

revoke all on function public.request_booking_cancellation(uuid, text) from public, anon;
grant execute on function public.request_booking_cancellation(uuid, text) to authenticated;
revoke all on function public.cancel_booking_cancellation_request(uuid) from public, anon;
grant execute on function public.cancel_booking_cancellation_request(uuid) to authenticated;
revoke all on function public.approve_booking_cancellation(uuid) from public, anon;
grant execute on function public.approve_booking_cancellation(uuid) to authenticated;
revoke all on function public.decline_booking_cancellation(uuid) from public, anon;
grant execute on function public.decline_booking_cancellation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- request_booking_change(): 2-hour lead time, 0-95 slot range, and a
-- plate-only change no longer counts as "material" - only route/date/slot
-- changes reset the booking back to pending and re-run the lead-time
-- check. That's what makes "fill in the plate on the day of the trip"
-- possible: the trip's slot can be minutes away by then.
-- ---------------------------------------------------------------------------
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
  v_plate text := nullif(btrim(coalesce(p_plate_no, '')), '');
  v_material boolean;
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
  if v_booking.cancellation_requested_at is not null then
    raise exception
      'A cancellation request is pending for this booking - withdraw it first.';
  end if;

  if coalesce(btrim(p_route), '') = '' then
    raise exception 'Route is required.';
  end if;
  if p_slot is null or p_slot < 0 or p_slot > 95 then
    raise exception 'Slot must be between 0 and 95.';
  end if;
  if p_booking_date is null or p_booking_date < v_today then
    raise exception 'Booking date cannot be in the past.';
  end if;

  v_material := (
    btrim(p_route) is distinct from v_booking.route
    or p_booking_date is distinct from v_booking.booking_date
    or p_slot is distinct from v_booking.slot
  );

  if v_material then
    if public.slot_start_at(v_booking.booking_date, v_booking.slot) < now() + interval '2 hours' then
      raise exception
        'This booking starts within 2 hours and can no longer be changed.';
    end if;
    if public.slot_start_at(p_booking_date, p_slot) < now() + interval '2 hours' then
      raise exception 'Please choose a time at least 2 hours from now.';
    end if;
  end if;

  if v_plate is not null then
    if not exists (
      select 1 from public.vehicles v
      where v.operator_id = auth.uid()
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and (v.cpc_validity is null or v.cpc_validity >= current_date)
        and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
        and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(v_plate), '[^A-Z0-9]', '', 'g')
        and public.vehicle_matches_route(v.route, p_route)
    ) then
      raise exception
        'That vehicle isn''t registered for this route (or its CPC has expired). Choose a vehicle registered for %, or pick a different route.', p_route;
    end if;
  end if;

  v_was_approved := (v_booking.status = 'approved');

  if v_material then
    update public.bookings set
      route               = btrim(p_route),
      plate_no            = v_plate,
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
  else
    -- Plate-only update: status, approval and assigned bay are untouched,
    -- and the lead-time check above was skipped entirely.
    update public.bookings set
      plate_no       = v_plate,
      revision_count = revision_count + 1,
      last_edited_at = now()
    where id = p_booking_id;
  end if;
end;
$$;

notify pgrst, 'reload schema';
