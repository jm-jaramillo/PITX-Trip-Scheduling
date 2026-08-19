-- Editing a vehicle - even fixing a typo in Sticker No. - always reverted
-- it to pending and dropped it out of the booking form's plate list,
-- since request_vehicle_change() unconditionally reset status/decided_*
-- on every save. That's the right behavior for a change that actually
-- affects what staff approved (plate, route, the OR/CR-verified
-- document fields) - it's needless friction for a purely descriptive
-- correction that has nothing to do with what was vetted.
--
-- Splits the vehicle's fields into two groups:
--   - "Material" - identity/registration fields staff actually verify
--     against the LTO OR/CR and LTFRB CPC paperwork: plate_no, route,
--     case_number, mv_file_number, or_number, cr_number, chassis_no,
--     franchise, cpc_validity, orcr_validity, date_granted, date_expiry.
--     Changing any of these still reverts the vehicle to pending, same
--     as before - the whole point of approval is verifying these.
--   - "Cosmetic" - descriptive/administrative fields nothing was
--     verified against: bus_number, seating_capacity, seat_type,
--     aircon, sticker_no, and the supporting document. Changing only
--     these no longer resets status/decided_by/decided_at/
--     rejection_reason - an approved vehicle stays approved.
--
-- revision_count still increments either way (it's "how many times has
-- this been edited," not "how many times did it need re-approval") and
-- previously_approved is only touched when the vehicle was actually
-- approved and is now being reset to pending, same logic as before.
--
-- Run after 0033_trip_numbers.sql.

create or replace function public.request_vehicle_change(p_vehicle_id uuid, p_plate_no text, p_case_number text, p_mv_file_number text, p_or_number text, p_cr_number text, p_route text, p_bus_number text, p_seating_capacity integer, p_seat_type text, p_aircon boolean, p_date_granted date, p_date_expiry date, p_supporting_doc_path text, p_supporting_doc_name text, p_chassis_no text, p_franchise text, p_cpc_validity date, p_orcr_validity date, p_sticker_no text)
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
  v_new_or_number text := nullif(btrim(coalesce(p_or_number, '')), '');
  v_new_cr_number text := nullif(btrim(coalesce(p_cr_number, '')), '');
  v_new_route text := nullif(btrim(coalesce(p_route, '')), '');
  v_new_chassis_no text := nullif(btrim(coalesce(p_chassis_no, '')), '');
  v_new_franchise text := nullif(btrim(coalesce(p_franchise, '')), '');
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
  if p_seat_type is not null and p_seat_type not in ('2x2', '2x3') then
    raise exception 'Seat type must be 2x2 or 2x3.';
  end if;

  v_material_changed :=
    v_vehicle.plate_no is distinct from v_new_plate_no
    or v_vehicle.route is distinct from v_new_route
    or v_vehicle.case_number is distinct from v_new_case_number
    or v_vehicle.mv_file_number is distinct from v_new_mv_file_number
    or v_vehicle.or_number is distinct from v_new_or_number
    or v_vehicle.cr_number is distinct from v_new_cr_number
    or v_vehicle.chassis_no is distinct from v_new_chassis_no
    or v_vehicle.franchise is distinct from v_new_franchise
    or v_vehicle.cpc_validity is distinct from p_cpc_validity
    or v_vehicle.orcr_validity is distinct from p_orcr_validity
    or v_vehicle.date_granted is distinct from p_date_granted
    or v_vehicle.date_expiry is distinct from p_date_expiry;

  v_was_approved := (v_vehicle.status = 'approved');

  update public.vehicles set
    plate_no             = v_new_plate_no,
    case_number          = v_new_case_number,
    mv_file_number       = v_new_mv_file_number,
    or_number            = v_new_or_number,
    cr_number            = v_new_cr_number,
    route                = v_new_route,
    bus_number           = nullif(btrim(coalesce(p_bus_number, '')), ''),
    seating_capacity     = p_seating_capacity,
    seat_type            = p_seat_type,
    aircon               = p_aircon,
    date_granted         = p_date_granted,
    date_expiry          = p_date_expiry,
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

comment on function public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date, text, text, text, text, date, date, text) is
  'Edits a vehicle. Only reverts it to pending (clearing the prior '
  'decision) if a "material" field actually changed - plate, route, or '
  'any LTO OR/CR-verified document field. A purely cosmetic edit '
  '(bus number, seating, seat type, aircon, sticker no., supporting '
  'doc) leaves an approved vehicle approved.';
