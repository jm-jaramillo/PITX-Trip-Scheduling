-- list_operator_vehicles() (0016) feeds both the transfer dialog's plate
-- dropdown and request_booking_transfer()'s server-side validation of the
-- new plate - it needs the same LTFRB eligibility rule the booking form
-- itself applies (migration 0021), or an inactive/no_record vehicle from
-- the masterlist import could still be transferred into a live booking.
--
-- CREATE OR REPLACE is fine here - same name, args, and return columns,
-- only the body changes.
--
-- Run this after 0021_vehicle_ltfrb_status.sql.

create or replace function public.list_operator_vehicles(p_username text)
returns table (plate_no text, bus_number text)
language sql
security definer
set search_path = public
stable
as $$
  select v.plate_no, v.bus_number
  from public.vehicles v
  join public.profiles p on p.id = v.operator_id
  where lower(p.username) = lower(btrim(p_username))
    and p.role = 'operator'
    and v.status = 'approved'
    and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
  order by v.plate_no;
$$;
