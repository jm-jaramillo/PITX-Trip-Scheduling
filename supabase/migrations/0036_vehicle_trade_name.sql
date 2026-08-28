-- Some operators run more than one trade name (DBA) under a single
-- account - different vehicles registered to the same operator can
-- belong to different trades. `trade_name` lives on the vehicle (not
-- the operator profile), since that's the level it actually varies at.
--
-- A booking snapshots the trade name of whichever vehicle/plate it's
-- for, the same way it already snapshots `operator_name` - so the
-- booking's own display always reflects what was true when it was
-- made/last changed, not whatever the vehicle's trade name happens to
-- be today. A trigger keeps this snapshot in sync automatically
-- whenever a booking's plate_no is set or changed (insert, a plate
-- change via request_booking_change(), or a transfer's plate/operator
-- change via approve_booking_transfer()) - callers don't compute or
-- pass trade_name themselves, so there's exactly one place this logic
-- lives.
--
-- Run after 0035_vehicle_registration_redesign.sql.

alter table public.vehicles
  add column if not exists trade_name text;

comment on column public.vehicles.trade_name is
  'Optional DBA/trade name this specific vehicle operates under - only '
  'needed when an operator runs more than one trade under one account. '
  'Null means "same as the operator''s own name."';

alter table public.bookings
  add column if not exists trade_name text,
  add column if not exists previous_trade_name text;

comment on column public.bookings.trade_name is
  'Snapshot of the booked vehicle''s trade_name at the time the plate '
  'was set/last changed - kept in sync by trg_assign_booking_trade_name, '
  'not set directly by callers.';
comment on column public.bookings.previous_trade_name is
  'The trade name struck through next to the new one after a transfer, '
  'same pattern as previous_operator_name - set only by '
  'approve_booking_transfer().';

-- Recomputes trade_name from the operator's matching vehicle whenever a
-- booking is inserted or its plate_no changes (covers plain inserts,
-- request_booking_change()'s plate/route edits, and
-- approve_booking_transfer()'s operator_id+plate_no swap, since all
-- three write plate_no through a normal INSERT/UPDATE this trigger
-- sees - no per-caller duplication needed). Referencing OLD in a
-- trigger fired for INSERT is safe in PL/pgSQL: OLD is simply NULL
-- there, so `new.plate_no is distinct from old.plate_no` is true
-- (correctly forcing the lookup) rather than raising an error.
create or replace function public.assign_booking_trade_name()
returns trigger
language plpgsql
as $$
begin
  if new.plate_no is distinct from old.plate_no then
    select v.trade_name into new.trade_name
    from public.vehicles v
    where v.operator_id = new.operator_id
      and regexp_replace(upper(v.plate_no), '[^A-Z0-9]', '', 'g')
        = regexp_replace(upper(new.plate_no), '[^A-Z0-9]', '', 'g')
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_assign_booking_trade_name on public.bookings;
create trigger trg_assign_booking_trade_name
  before insert or update on public.bookings
  for each row
  execute function public.assign_booking_trade_name();

-- approve_booking_transfer() (latest definition: 0012) already sets
-- previous_operator_name/operator_name/plate_no in one UPDATE - the
-- trigger above picks up the new plate_no/operator_id from that same
-- UPDATE and recomputes trade_name on its own; this just adds the
-- symmetric previous_trade_name snapshot alongside
-- previous_operator_name. Body is otherwise byte-for-byte the same as
-- 0012's version - signature unchanged, so CREATE OR REPLACE.
create or replace function public.approve_booking_transfer(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.booking_transfers%rowtype;
  v_booking public.bookings%rowtype;
  v_to_name text;
begin
  if not public.is_staff() then
    raise exception 'Only PITX staff can decide on transfers.';
  end if;

  select * into v_transfer
  from public.booking_transfers
  where id = p_transfer_id and status = 'pending'
  for update;

  if v_transfer.id is null then
    raise exception 'Transfer request not found or already decided.';
  end if;
  if v_transfer.recipient_response <> 'accepted' then
    raise exception 'The receiving operator has not confirmed this transfer yet.';
  end if;

  select * into v_booking from public.bookings where id = v_transfer.booking_id for update;
  if v_booking.id is null then
    raise exception 'The original booking no longer exists.';
  end if;

  select coalesce(operator_name, username) into v_to_name
  from public.profiles where id = v_transfer.to_operator_id;

  update public.bookings set
    previous_operator_name = v_booking.operator_name,
    previous_trade_name = v_booking.trade_name,
    operator_id = v_transfer.to_operator_id,
    operator_name = coalesce(v_to_name, v_booking.operator_name),
    plate_no = v_transfer.new_plate_no
  where id = v_booking.id;

  update public.booking_transfers set
    status = 'approved',
    decided_by = auth.uid(),
    decided_at = now()
  where id = p_transfer_id;
end;
$$;

-- request_vehicle_change() gains a p_trade_name param - a new
-- parameter changes the signature, so drop + recreate rather than
-- CREATE OR REPLACE, same as every prior field-set change to this
-- function. Body is 0035's version verbatim plus trade_name wherever
-- body_number (the most similar cosmetic identity field) appears.
drop function if exists public.request_vehicle_change(
  uuid, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
);

create function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_case_number text,
  p_mv_file_number text,
  p_route text,
  p_body_number text,
  p_trade_name text,
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
    trade_name           = nullif(btrim(coalesce(p_trade_name, '')), ''),
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
  uuid, text, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) is
  'Edits a vehicle. Only reverts it to pending (clearing the prior '
  'decision) if a "material" field actually changed - plate, route, or '
  'any CPC/franchise-verified field (case/MV file/chassis/franchise '
  'numbers, CPC validity, OR/CR validity, CPC-EOV). A purely cosmetic '
  'edit (body number, trade name, seating, seat configuration, bus '
  'type, year/make, origin/destination, remarks, sticker no., '
  'supporting doc) leaves an approved vehicle approved.';

revoke all on function public.request_vehicle_change(
  uuid, text, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) from public, anon;
grant execute on function public.request_vehicle_change(
  uuid, text, text, text, text, text, text, integer, text, text, boolean, date,
  integer, text, text, text, text, text, text, text, text, date, date, text
) to authenticated;

notify pgrst, 'reload schema';
