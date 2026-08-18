-- Tracks each vehicle's LTFRB unit status from PITX's own masterlist
-- (separate from `status`, which is this app's own pending/approved/
-- rejected approval workflow - a vehicle can be `approved` here and still
-- be `inactive` at LTFRB, e.g. a unit that's been re-tagged elsewhere).
-- Null for vehicles registered normally through the operator's own "My
-- vehicles" page - only the bulk masterlist import populates this.
--
-- Run this after 0003_vehicles.sql.

alter table public.vehicles
  add column if not exists ltfrb_status text
    check (ltfrb_status in ('active', 'inactive', 'no_record', 'ltfrb_verified'));

comment on column public.vehicles.ltfrb_status is
  'LTFRB unit status from the PITX masterlist import - active/ltfrb_verified '
  'units are eligible for the booking form''s plate list (see dashboard.html), '
  'inactive/no_record ones are not. Null for vehicles registered directly by '
  'the operator, which are always eligible regardless of this column.';

-- The masterlist import is a distinct provenance from a manually-entered or
-- scanned vehicle - widen the existing source check rather than overload
-- 'manual' for ~1,900 rows that didn't come through either normal path.
alter table public.vehicles drop constraint if exists vehicles_source_check;
alter table public.vehicles
  add constraint vehicles_source_check
    check (source in ('scanned', 'manual', 'masterlist_import'));
