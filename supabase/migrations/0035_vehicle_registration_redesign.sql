-- Reworks the vehicle registration record to match PITX's updated
-- intake form:
--   - Drops OR No., CR No., Date granted, Date expiry - superseded by
--     the CPC/franchise fields (case/MV file/chassis/franchise/sticker,
--     CPC validity, OR/CR validity) already tracked separately.
--   - Renames bus_number -> body_number (label change on the form).
--   - Replaces the aircon boolean with a bus_type category (Ordinary,
--     Aircon, Deluxe, Luxury).
--   - Widens seat_type from 2x2/2x3 to also allow 1x1/1x3.
--   - Adds a CPC Extension of Validity flag + its own validity date,
--     Year/Make, Origin/Destination, and a free-text Remarks field.
--   - A vehicle whose CPC or CPC-EOV validity date has passed can no
--     longer be used to book a slot - same enforcement pattern as the
--     existing LTFRB-eligibility check (RLS is the real gate; the
--     client-side dropdown filter in dashboard.html is UX only).
--
-- Run after 0034_vehicle_change_cosmetic_fields.sql.

alter table public.vehicles
  drop column if exists or_number,
  drop column if exists cr_number,
  drop column if exists date_granted,
  drop column if exists date_expiry;

alter table public.vehicles
  rename column bus_number to body_number;

alter table public.vehicles
  drop column if exists aircon;

alter table public.vehicles
  add column if not exists bus_type text,
  add column if not exists cpc_eov boolean not null default false,
  add column if not exists cpc_eov_validity date,
  add column if not exists vehicle_year smallint,
  add column if not exists vehicle_make text,
  add column if not exists origin text,
  add column if not exists destination text,
  add column if not exists remarks text,
  add column if not exists seat_layout_path text,
  add column if not exists seat_layout_name text;

comment on column public.vehicles.seat_layout_path is
  'Storage path (vehicle-docs bucket) of an uploaded seat configuration '
  'layout diagram/photo - optional, cosmetic (like supporting_doc_path), '
  'set via a direct operator-owns-row update rather than through '
  'request_vehicle_change() to keep that RPC''s already-large parameter '
  'list from growing further.';

-- Batch-uploaded vehicles (this redesign''s CSV import) need their own
-- source value, same as 'scanned'/'manual'/'masterlist_import'.
alter table public.vehicles drop constraint if exists vehicles_source_check;
alter table public.vehicles
  add constraint vehicles_source_check
    check (source in ('scanned', 'manual', 'masterlist_import', 'batch_import'));

alter table public.vehicles
  drop constraint if exists vehicles_bus_type_check,
  add constraint vehicles_bus_type_check
    check (bus_type is null or bus_type in ('ordinary', 'aircon', 'deluxe', 'luxury'));

-- seat_type's original check (added alongside the column, unnamed by us
-- so Postgres picked an auto name) only allowed 2x2/2x3 - widen it to
-- the same four layouts the registration form now offers. The
-- constraint name below is the default Postgres would have generated
-- for a column-level check on `seat_type`, matching migration 0008.
alter table public.vehicles
  drop constraint if exists vehicles_seat_type_check,
  add constraint vehicles_seat_type_check
    check (seat_type is null or seat_type in ('1x1', '2x2', '2x3', '1x3'));

alter table public.vehicles
  drop constraint if exists vehicles_cpc_eov_validity_check,
  add constraint vehicles_cpc_eov_validity_check
    check (not cpc_eov or cpc_eov_validity is not null);

comment on column public.vehicles.cpc_eov is
  'Whether this vehicle''s CPC has an Extension of Validity on file. '
  'When true, cpc_eov_validity must be set.';
comment on column public.vehicles.cpc_eov_validity is
  'Expiry date of the CPC Extension of Validity - required when '
  'cpc_eov is true. A vehicle can''t book a slot once this (or '
  'cpc_validity) has passed, same as the LTFRB-eligibility check.';

-- request_vehicle_change()'s parameter list changes (OR/CR/date_granted/
-- date_expiry params dropped, bus_number renamed, several added) - drop
-- + recreate, not CREATE OR REPLACE, same as every prior field-set
-- change to this function (0006/0008/0015/0019/0023/0034).
drop function if exists public.request_vehicle_change(
  uuid, text, text, text, text, text, text, text, integer, text, boolean,
  date, date, text, text, text, text, date, date, text
);

create function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_case_number text,
  p_mv_file_number text,
  p_route text,
  p_body_number text,
  p_seating_capacity integer,
  p_seat_type text,
  p_bus_type text,
  p_cpc_eov boolean,
  p_cpc_eov_validity date,
  p_vehicle_year integer,
  p_vehicle_make text,
  p_origin text,
  p_destination text,
  p_remarks text,
  p_supporting_doc_path text,
  p_supporting_doc_name text,
  p_chassis_no text,
  p_franchise text,
  p_cpc_validity date,
  p_orcr_validity date,
  p_sticker_no text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_was_approved boolean;
  v_new_plate_no text := btrim(p_plate_no);
  v_new_case_number text := nullif(btrim(coalesce(p_case_number, '')), '');
  v_new_mv_file_number text := nullif(btrim(coalesce(p_mv_file_number, '')), '');
  v_new_route text := nullif(btrim(coalesce(p_route, '')), '');
  v_new_chassis_no text := nullif(btrim(coalesce(p_chassis_no, '')), '');
  v_new_franchise text := nullif(btrim(coalesce(p_franchise, '')), '');
  v_new_cpc_eov boolean := coalesce(p_cpc_eov, false);
  v_material_changed boolean;
begin
  select * into v_vehicle
  from public.vehicles
  where id = p_vehicle_id and operator_id = auth.uid()
  for update;

  if v_vehicle.id is null then
    raise exception 'Vehicle not found.';
  end if;
  if v_vehicle.status not in ('pending', 'approved') then
    raise exception
      'Only pending or approved vehicles can be edited. Register a new one instead.';
  end if;

  if coalesce(v_new_plate_no, '') = '' then
    raise exception 'Plate number is required.';
  end if;
  if p_seating_capacity is not null and p_seating_capacity <= 0 then
    raise exception 'Seating capacity must be positive.';
  end if;
  if p_seat_type is not null and p_seat_type not in ('1x1', '2x2', '2x3', '1x3') then
    raise exception 'Seat configuration must be 1x1, 2x2, 2x3, or 1x3.';
  end if;
  if p_bus_type is not null and p_bus_type not in ('ordinary', 'aircon', 'deluxe', 'luxury') then
    raise exception 'Bus type must be Ordinary, Aircon, Deluxe, or Luxury.';
  end if;
  if v_new_cpc_eov and p_cpc_eov_validity is null then
    raise exception 'CPC Extension of Validity date is required when the extension is marked yes.';
  end if;

  v_material_changed :=
    v_vehicle.plate_no is distinct from v_new_plate_no
    or v_vehicle.route is distinct from v_new_route
    or v_vehicle.case_number is distinct from v_new_case_number
    or v_vehicle.mv_file_number is distinct from v_new_mv_file_number
    or v_vehicle.chassis_no is distinct from v_new_chassis_no
    or v_vehicle.franchise is distinct from v_new_franchise
    or v_vehicle.cpc_validity is distinct from p_cpc_validity
    or v_vehicle.orcr_validity is distinct from p_orcr_validity
    or v_vehicle.cpc_eov is distinct from v_new_cpc_eov
    or v_vehicle.cpc_eov_validity is distinct from p_cpc_eov_validity;

  v_was_approved := (v_vehicle.status = 'approved');

  update public.vehicles set
    plate_no             = v_new_plate_no,
    case_number          = v_new_case_number,
    mv_file_number       = v_new_mv_file_number,
    route                = v_new_route,
    body_number          = nullif(btrim(coalesce(p_body_number, '')), ''),
    seating_capacity     = p_seating_capacity,
    seat_type            = p_seat_type,
    bus_type             = p_bus_type,
    cpc_eov              = v_new_cpc_eov,
    cpc_eov_validity     = case when v_new_cpc_eov then p_cpc_eov_validity else null end,
    vehicle_year         = p_vehicle_year,
    vehicle_make         = nullif(btrim(coalesce(p_vehicle_make, '')), ''),
    origin               = nullif(btrim(coalesce(p_origin, '')), ''),
    destination          = nullif(btrim(coalesce(p_destination, '')), ''),
    remarks              = nullif(btrim(coalesce(p_remarks, '')), ''),
    supporting_doc_path  = p_supporting_doc_path,
    supporting_doc_name  = p_supporting_doc_name,
    chassis_no           = v_new_chassis_no,
    franchise            = v_new_franchise,
    cpc_validity         = p_cpc_validity,
    orcr_validity        = p_orcr_validity,
    sticker_no           = nullif(btrim(coalesce(p_sticker_no, '')), ''),
    status               = case when v_material_changed then 'pending' else status end,
    rejection_reason     = case when v_material_changed then null else rejection_reason end,
    decided_by           = case when v_material_changed then null else decided_by end,
    decided_at           = case when v_material_changed then null else decided_at end,
    previously_approved  = previously_approved or (v_material_changed and v_was_approved),
    revision_count       = revision_count + 1
  where id = p_vehicle_id;
end;
$$;

comment on function public.request_vehicle_change(
  uuid, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) is
  'Edits a vehicle. Only reverts it to pending (clearing the prior '
  'decision) if a "material" field actually changed - plate, route, or '
  'any CPC/franchise-verified field (case/MV file/chassis/franchise '
  'numbers, CPC validity, OR/CR validity, CPC-EOV). A purely cosmetic '
  'edit (body number, seating, seat configuration, bus type, year/make, '
  'origin/destination, remarks, sticker no., supporting doc) leaves an '
  'approved vehicle approved.';

revoke all on function public.request_vehicle_change(
  uuid, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) from public, anon;
grant execute on function public.request_vehicle_change(
  uuid, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) to authenticated;

-- Booking eligibility everywhere it's checked now also requires the
-- vehicle's CPC (and, if it has one, its CPC-EOV) not be expired -
-- same "RLS is the real gate" pattern as the existing LTFRB check, and
-- kept in the same shape as that check so the two read as one
-- eligibility rule, not two.
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
        and (v.cpc_validity is null or v.cpc_validity >= current_date)
        and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
        and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
          = regexp_replace(upper(bookings.plate_no), '[^A-Z0-9]', '', 'g')
        and public.vehicle_matches_route(v.route, bookings.route)
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

  if not exists (
    select 1 from public.vehicles v
    where v.operator_id = auth.uid()
      and v.status = 'approved'
      and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
      and (v.cpc_validity is null or v.cpc_validity >= current_date)
      and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
      and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
        = regexp_replace(upper(p_plate_no), '[^A-Z0-9]', '', 'g')
      and public.vehicle_matches_route(v.route, p_route)
  ) then
    raise exception
      'That vehicle isn''t registered for this route (or its CPC has expired). Choose a vehicle registered for %, or pick a different route.', p_route;
  end if;

  v_was_approved := (v_booking.status = 'approved');

  update public.bookings set
    route               = btrim(p_route),
    plate_no            = btrim(p_plate_no),
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
end;
$$;

-- list_operator_accounts()/list_operator_vehicles() (transfer dialog):
-- same CPC-expiry eligibility added, and bus_number -> body_number in
-- the returned column. Parameter lists are unchanged, but
-- list_operator_vehicles()'s RETURN TABLE column changed, which
-- Postgres won't let CREATE OR REPLACE touch - drop + recreate.
create or replace function public.list_operator_accounts(p_route text)
returns table (username text, operator_name text)
language sql
security definer
set search_path = public
stable
as $$
  select p.username, p.operator_name
  from public.profiles p
  where p.role = 'operator'
    and p.id <> auth.uid()
    and exists (
      select 1 from public.vehicles v
      where v.operator_id = p.id
        and v.status = 'approved'
        and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
        and (v.cpc_validity is null or v.cpc_validity >= current_date)
        and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
        and public.vehicle_matches_route(v.route, p_route)
    )
  order by coalesce(p.operator_name, p.username);
$$;

drop function if exists public.list_operator_vehicles(text, text);

create function public.list_operator_vehicles(p_username text, p_route text)
returns table (plate_no text, body_number text)
language sql
security definer
set search_path = public
stable
as $$
  select v.plate_no, v.body_number
  from public.vehicles v
  join public.profiles p on p.id = v.operator_id
  where lower(p.username) = lower(btrim(p_username))
    and p.role = 'operator'
    and v.status = 'approved'
    and (v.ltfrb_status is null or v.ltfrb_status in ('active', 'ltfrb_verified'))
    and (v.cpc_validity is null or v.cpc_validity >= current_date)
    and (not v.cpc_eov or v.cpc_eov_validity is null or v.cpc_eov_validity >= current_date)
    and public.vehicle_matches_route(v.route, p_route)
  order by v.plate_no;
$$;

comment on function public.list_operator_vehicles(text, text) is
  'A specific operator''s approved, LTFRB-eligible, CPC-current vehicles '
  'registered for the given route - feeds the transfer dialog''s plate '
  'dropdown, narrowed the same way the booking form narrows the '
  'requesting operator''s own plate options.';

revoke all on function public.list_operator_vehicles(text, text) from public, anon;
grant execute on function public.list_operator_vehicles(text, text) to authenticated;

notify pgrst, 'reload schema';
