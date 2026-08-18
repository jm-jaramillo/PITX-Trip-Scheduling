-- 0026's bookings_insert_own policy had a real bug: inside the
-- correlated EXISTS subquery, the bare `plate_no` and `route` references
-- (meant to mean the row being inserted) got shadowed by the subquery's
-- own `vehicles.plate_no`/`vehicles.route` columns of the same name -
-- Postgres resolved them to the innermost scope, so the check silently
-- became "does this vehicle's plate/route equal itself", which is
-- always true. Confirmed live: an insert with a deliberately mismatched
-- vehicle/route went through with no error.
--
-- Fixed by qualifying the outer row explicitly as `bookings.plate_no` /
-- `bookings.route` - the table name itself works as the row's own
-- qualifier in a WITH CHECK expression when no alias was given.
--
-- Run after 0026_vehicle_route_required.sql.

drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (
    operator_id = auth.uid()
    and status = 'pending'
    and public.slot_start_at(booking_date, slot) >= now() + interval '4 hours'
    and exists (
      select 1 from public.vehicles v
      where v.operator_id = auth.uid()
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(bookings.plate_no), '[^A-Z0-9]', '', 'g')
        and public.vehicle_matches_route(v.route, bookings.route)
    )
  );

notify pgrst, 'reload schema';
