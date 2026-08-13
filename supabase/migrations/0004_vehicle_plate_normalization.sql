-- Fixes a gap in the vehicles_operator_plate_unique index: it uppercased
-- the plate but didn't strip whitespace, so "NGP 2481" and "ngp2481"
-- registered as two different vehicles instead of being caught as
-- duplicates. Compares on letters+digits only.
--
-- Run after 0003_vehicles.sql.

drop index if exists public.vehicles_operator_plate_unique;

create unique index if not exists vehicles_operator_plate_unique
  on public.vehicles (operator_id, regexp_replace(upper(plate_no), '[^A-Z0-9]', '', 'g'));

notify pgrst, 'reload schema';
