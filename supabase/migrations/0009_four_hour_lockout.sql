-- Enforces a 4-hour lead time on operator-initiated booking activity:
--   - A new booking request's slot must be at least 4 hours away.
--   - An existing booking can no longer be changed once its currently
--     scheduled slot is within 4 hours - and the new slot being requested
--     must itself be at least 4 hours out.
--
-- Deliberately does NOT restrict staff approve/reject, or operator
-- cancellation - only what was asked: creating and changing a booking.
--
-- Run after 0008_official_form_fields.sql.

-- ---------------------------------------------------------------------------
-- slot_start_at: the actual UTC instant a (booking_date, slot) pair
-- represents. PITX runs on Philippine time, and slot is a 30-minute index
-- in that local time - `timestamp ... AT TIME ZONE 'Asia/Manila'` is the
-- idiom for "interpret this naive value as being in that zone", giving
-- back a real timestamptz comparable to now().
-- ---------------------------------------------------------------------------
create or replace function public.slot_start_at(p_booking_date date, p_slot smallint)
returns timestamptz
language sql
immutable
as $$
  select (p_booking_date::timestamp + (p_slot * interval '30 minutes'))
    at time zone 'Asia/Manila';
$$;

-- ---------------------------------------------------------------------------
-- New bookings: the requested slot must be >= 4 hours away at submission
-- time. This lives in the INSERT policy's WITH CHECK (not the UPDATE
-- policies), so it only ever applies to creating a request - staff
-- approving/rejecting through bookings_staff_update is untouched.
-- ---------------------------------------------------------------------------
drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (
    operator_id = auth.uid()
    and status = 'pending'
    and public.slot_start_at(booking_date, slot) >= now() + interval '4 hours'
  );

-- ---------------------------------------------------------------------------
-- request_booking_change: add the two lead-time checks. Signature is
-- unchanged from 0007, so CREATE OR REPLACE is fine here (no drop needed).
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
  -- PITX runs on Philippine time; comparing against UTC's current_date would
  -- wrongly reject same-day bookings made after 4pm local.
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

  v_was_approved := (v_booking.status = 'approved');

  update public.bookings set
    route               = btrim(p_route),
    plate_no            = btrim(p_plate_no),
    booking_date        = p_booking_date,
    slot                = p_slot,
    -- Back to the queue; the previously held bay is released so another
    -- operator can be approved into it while this change is reviewed.
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
