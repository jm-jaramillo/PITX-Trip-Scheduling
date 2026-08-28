-- Correction to migration 0039: a still-*pending* booking never had
-- anything approved to lose, so cancelling it doesn't need staff review -
-- that's the bookings_cancel_own policy from migration 0001, dropped in
-- 0039 by mistake along with the *approved*-booking instant-cancel it was
-- never meant to allow in the first place (bookings_cancel_own's own
-- `using` clause already restricted it to status = 'pending'). Restore it
-- unchanged, and make request_booking_cancellation() (the approval-gated
-- path) explicitly an *approved*-booking-only operation, so a pending
-- request has exactly one cancel path, not two overlapping ones.
drop policy if exists bookings_cancel_own on public.bookings;
create policy bookings_cancel_own on public.bookings
  for update
  using (operator_id = auth.uid() and status = 'pending')
  with check (operator_id = auth.uid() and status = 'cancelled');

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
  if v_booking.status = 'pending' then
    raise exception 'A pending request can be cancelled directly - no approval needed.';
  end if;
  if v_booking.status != 'approved' then
    raise exception 'Only an approved booking can be cancelled this way.';
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

notify pgrst, 'reload schema';
