-- The new "All trips" board on my-schedule.html (an operator-facing
-- version of staff's PIDS Schedule board - see #80/CHANGELOG) needs every
-- operator to be able to read every OTHER operator's confirmed trips for
-- a given day, not just their own. bookings_select (migration 0001) only
-- ever let an operator see their own rows (or staff see everyone's) -
-- this widens it to also allow any signed-in user to see a booking once
-- it's a real, confirmed trip: currently approved, or cancelled after
-- having been approved at some point. That's the same "confirmed trips
-- only" rule the board's own query already applies - a pending request
-- (someone else's still-unapproved ask for a slot) stays private to its
-- own operator and to staff, exactly as before.
drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select
  using (
    operator_id = auth.uid()
    or public.is_staff()
    or status = 'approved'
    or (status = 'cancelled' and previously_approved)
  );

notify pgrst, 'reload schema';
