-- Bug in migration 0039: approve_booking_cancellation() cancelled the
-- booking but never cleared cancellation_requested_at, so
-- cancellation_requested_at is not null (the "has a pending cancellation
-- request" flag) stayed set forever - the now-cancelled booking never
-- left staff's Cancellation requests queue or its badge count, even
-- though there was nothing left to decide. cancellation_reason is left
-- alone; it's still useful context on an already-cancelled booking.
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
    status                    = 'cancelled',
    assigned_bay_id           = null,
    decided_by                = auth.uid(),
    decided_at                = now(),
    cancellation_requested_at = null
  where id = p_booking_id;
end;
$$;

notify pgrst, 'reload schema';
