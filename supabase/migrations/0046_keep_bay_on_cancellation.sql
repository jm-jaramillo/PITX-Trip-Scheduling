-- approve_booking_cancellation() nulled assigned_bay_id to "release the
-- bay". Functionally that was never what released it: the uniqueness
-- constraint is a PARTIAL index scoped to approved rows
--
--   bookings_unique_approved_bay_slot ... WHERE status = 'approved'
--                                           AND assigned_bay_id IS NOT NULL
--
-- so the moment status flips to 'cancelled' the bay is free for reuse
-- whether or not the column still points at it. Every capacity check in
-- the app agrees - dashboard.html's gate-fullness hint and staff.html's
-- taken-bay map both filter status='approved' before reading
-- assigned_bay_id.
--
-- Nulling it did lose information, and that broke a report: the
-- Utilization page groups by the booking's bay to get its gate, so a
-- trip cancelled through the approval flow disappeared from the page
-- entirely and its "Cancelled after approval" column could never be
-- anything but zero. (The Schedule board was unaffected - it reads
-- previously_approved, not the bay.) Found in the #90 end-to-end test.
--
-- Keeping the bay also leaves a straight answer to "which bay did we
-- hold for this trip before it was cancelled", which staff had no way
-- to recover afterwards.
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

  -- previously_approved is set explicitly rather than left to whatever
  -- put it there before: it's what marks this as a cancellation of a
  -- real, confirmed trip (versus a request cancelled before it was ever
  -- approved), which is what the Schedule board and the Utilization
  -- report both key off.
  update public.bookings set
    status                    = 'cancelled',
    previously_approved       = true,
    decided_by                = auth.uid(),
    decided_at                = now(),
    cancellation_requested_at = null
  where id = p_booking_id;
end;
$$;

notify pgrst, 'reload schema';
