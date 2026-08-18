-- Five more fields from the paper registration form / LTFRB masterlist
-- that weren't captured before: chassis no., the franchise's own
-- number/description (distinct from `route`, which is the short
-- operating-route text), the CPC's own validity date (distinct from the
-- existing generic `date_expiry`, which stays as-is for whatever it was
-- already tracking), the OR/CR's validity date, and the PITX gate
-- sticker no.
--
-- Run after 0022_ltfrb_status_transfer_eligibility.sql.

alter table public.vehicles
  add column if not exists chassis_no text,
  add column if not exists franchise text,
  add column if not exists cpc_validity date,
  add column if not exists orcr_validity date,
  add column if not exists sticker_no text;

comment on column public.vehicles.chassis_no is 'Chassis/VIN number from the LTO OR/CR or masterlist.';
comment on column public.vehicles.franchise is 'The franchise''s own number/description - distinct from `route`.';
comment on column public.vehicles.cpc_validity is 'CPC (Certificate of Public Convenience) validity/expiry date.';
comment on column public.vehicles.orcr_validity is 'OR/CR validity/renewal date.';
comment on column public.vehicles.sticker_no is 'PITX gate sticker number.';

-- request_vehicle_change() needs the five new parameters so an operator
-- can edit them too - same drop-and-recreate reasoning as every prior
-- signature change (0005, 0015, 0018, 0019): Postgres can't alter a
-- function's parameter list in place, and this RPC is the only way an
-- operator can change any field on a vehicle they already registered
-- (migration 0005 dropped their direct UPDATE policy entirely).
drop function if exists public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date, text, text);

create or replace function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_case_number text,
  p_mv_file_number text,
  p_or_number text,
  p_cr_number text,
  p_route text,
  p_bus_number text,
  p_seating_capacity integer,
  p_seat_type text,
  p_aircon boolean,
  p_date_granted date,
  p_date_expiry date,
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
set search_path = public
as $$
declare
  v_status text;
  v_was_approved boolean;
begin
  select status into v_status
  from public.vehicles
  where id = p_vehicle_id and operator_id = auth.uid()
  for update;

  if v_status is null then
    raise exception 'Vehicle not found.';
  end if;
  if v_status not in ('pending', 'approved') then
    raise exception
      'Only pending or approved vehicles can be edited. Register a new one instead.';
  end if;

  if coalesce(btrim(p_plate_no), '') = '' then
    raise exception 'Plate number is required.';
  end if;
  if p_seating_capacity is not null and p_seating_capacity <= 0 then
    raise exception 'Seating capacity must be positive.';
  end if;
  if p_seat_type is not null and p_seat_type not in ('2x2', '2x3') then
    raise exception 'Seat type must be 2x2 or 2x3.';
  end if;

  v_was_approved := (v_status = 'approved');

  update public.vehicles set
    plate_no            = btrim(p_plate_no),
    case_number         = nullif(btrim(coalesce(p_case_number, '')), ''),
    mv_file_number      = nullif(btrim(coalesce(p_mv_file_number, '')), ''),
    or_number           = nullif(btrim(coalesce(p_or_number, '')), ''),
    cr_number           = nullif(btrim(coalesce(p_cr_number, '')), ''),
    route               = nullif(btrim(coalesce(p_route, '')), ''),
    bus_number          = nullif(btrim(coalesce(p_bus_number, '')), ''),
    seating_capacity    = p_seating_capacity,
    seat_type           = p_seat_type,
    aircon              = p_aircon,
    date_granted        = p_date_granted,
    date_expiry         = p_date_expiry,
    supporting_doc_path = p_supporting_doc_path,
    supporting_doc_name = p_supporting_doc_name,
    chassis_no          = nullif(btrim(coalesce(p_chassis_no, '')), ''),
    franchise           = nullif(btrim(coalesce(p_franchise, '')), ''),
    cpc_validity        = p_cpc_validity,
    orcr_validity       = p_orcr_validity,
    sticker_no          = nullif(btrim(coalesce(p_sticker_no, '')), ''),
    status               = 'pending',
    rejection_reason      = null,
    decided_by            = null,
    decided_at            = null,
    previously_approved   = previously_approved or v_was_approved,
    revision_count        = revision_count + 1
  where id = p_vehicle_id;
end;
$$;

revoke all on function public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date, text, text, text, text, date, date, text)
  from public, anon;
grant execute on function public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date, text, text, text, text, date, date, text)
  to authenticated;

notify pgrst, 'reload schema';
