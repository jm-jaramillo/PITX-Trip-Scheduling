-- A single vehicle can't physically serve two trips back to back - the
-- same bus/plate can't be in adjacent 15-minute slots on the same date
-- (one departing right as the other would need to). This is checked
-- wherever a plate actually gets attached to a booking: the (now rare,
-- since #81 made plate_no optional at creation) case of a plate being
-- set directly on insert, and - the common path now - setting/changing
-- the plate later via request_booking_change(). Only pending/approved
-- bookings count as real scheduling intent; cancelled/rejected ones
-- don't block anything. Deliberately scoped to the same calendar date
-- only - a booking at slot 0 and another at slot 95 the day before are
-- adjacent in wall-clock time but aren't checked against each other,
-- since that cross-midnight case is rare enough not to be worth the
-- extra query shape here.
drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (
    operator_id = auth.uid()
    and status = 'pending'
    and public.slot_start_at(booking_date, slot) >= now() + interval '2 hours'
    and (
      plate_no is null
      or (
        exists (
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
        and not exists (
          select 1 from public.bookings b2
          where b2.operator_id = auth.uid()
            and b2.status in ('pending', 'approved')
            and b2.booking_date = bookings.booking_date
            and abs(b2.slot - bookings.slot) = 1
            and regexp_replace(upper(b2.plate_no), '[^A-Z0-9]', '', 'g')
              = regexp_replace(upper(bookings.plate_no), '[^A-Z0-9]', '', 'g')
        )
      )
    )
  );

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

    -- Same vehicle, adjacent 15-minute slot, same date - the same bus
    -- can't depart on two trips back to back. Checked against the final
    -- date/slot this booking will have (p_booking_date/p_slot - already
    -- equal to the current values when this is a plate-only change).
    if exists (
      select 1 from public.bookings b2
      where b2.id <> p_booking_id
        and b2.operator_id = auth.uid()
        and b2.status in ('pending', 'approved')
        and b2.booking_date = p_booking_date
        and abs(b2.slot - p_slot) = 1
        and regexp_replace(upper(b2.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(v_plate), '[^A-Z0-9]', '', 'g')
    ) then
      raise exception
        'That vehicle already has a booking in the adjacent time slot on this date - the same vehicle can''t serve two trips back to back.';
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
