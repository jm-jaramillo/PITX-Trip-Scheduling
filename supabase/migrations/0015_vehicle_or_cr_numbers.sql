-- Re-adds per-vehicle OR (Official Receipt) and CR (Certificate of
-- Registration) number fields, dropped in migration 0008 when the vehicle
-- table was replaced to match the paper form exactly. Turns out these are
-- still wanted per-vehicle (separate from operator_profiles.or_serial_number,
-- which is a company-level field from a different part of that form).
--
-- request_vehicle_change()'s signature changes, so it's dropped and
-- recreated rather than CREATE OR REPLACE'd, same reason as every prior
-- signature change in this project (Postgres doesn't allow changing a
-- function's parameter list in place).
--
-- Run after 0014_transfer_sender_snapshot.sql.

alter table public.vehicles
  add column if not exists or_number text,
  add column if not exists cr_number text;

drop function if exists public.request_vehicle_change(uuid, text, text, text, text, text, integer, text, boolean, date, date);

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
  p_date_expiry date
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
    status               = 'pending',
    rejection_reason      = null,
    decided_by            = null,
    decided_at            = null,
    previously_approved   = previously_approved or v_was_approved,
    revision_count        = revision_count + 1
  where id = p_vehicle_id;
end;
$$;

revoke all on function public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date)
  from public, anon;
grant execute on function public.request_vehicle_change(uuid, text, text, text, text, text, text, text, integer, text, boolean, date, date)
  to authenticated;

notify pgrst, 'reload schema';
