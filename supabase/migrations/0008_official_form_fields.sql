-- Restructures vehicle registration to match the official PITX/MWM
-- Terminals paper form exactly, and adds a one-time "operator profile" for
-- the company-level details at the top of that same form.
--
-- The vehicle table's field set is REPLACED, not extended: make_model,
-- body_type, or_number, cr_number, franchise_number, and free-text
-- seat_configuration are dropped (the paper form has no per-vehicle OR/CR -
-- that becomes a single operator-level "Serial Number (OR)" instead).
--
-- request_vehicle_change()'s signature changes completely, so it's dropped
-- and recreated rather than CREATE OR REPLACE'd, same reason as every
-- prior signature change in this project (Postgres doesn't allow changing
-- a function's parameter list in place).
--
-- Run after 0007_thirty_minute_slots.sql.

-- ---------------------------------------------------------------------------
-- operator_profiles: the company-level fields at the top of the form.
-- One row per operator account, filled in and edited freely by that
-- operator - there's no approval workflow here (nothing privileged to
-- protect, unlike a booking's bay or a vehicle's approval status), so a
-- plain RLS-scoped UPDATE is enough; no SECURITY DEFINER function needed.
-- ---------------------------------------------------------------------------
create table if not exists public.operator_profiles (
  operator_id uuid primary key references public.profiles (id) on delete cascade,
  company_name text,
  company_owner text,
  tin_no text,
  or_serial_number text,
  has_booking_system boolean not null default false,
  booking_system_name text,
  nau text,
  contact1_name text,
  contact1_number text,
  contact1_position text,
  contact2_name text,
  contact2_number text,
  contact2_position text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists operator_profiles_touch_updated_at on public.operator_profiles;
create trigger operator_profiles_touch_updated_at
  before update on public.operator_profiles
  for each row
  execute function public.touch_updated_at();

alter table public.operator_profiles enable row level security;

drop policy if exists operator_profiles_select on public.operator_profiles;
create policy operator_profiles_select on public.operator_profiles
  for select
  using (operator_id = auth.uid() or public.is_staff());

drop policy if exists operator_profiles_insert_own on public.operator_profiles;
create policy operator_profiles_insert_own on public.operator_profiles
  for insert
  with check (operator_id = auth.uid());

drop policy if exists operator_profiles_update_own on public.operator_profiles;
create policy operator_profiles_update_own on public.operator_profiles
  for update
  using (operator_id = auth.uid())
  with check (operator_id = auth.uid());

-- ---------------------------------------------------------------------------
-- vehicles: replace the field set with the paper form's per-vehicle table.
-- ---------------------------------------------------------------------------
alter table public.vehicles rename column body_number to bus_number;
alter table public.vehicles rename column seat_count to seating_capacity;
alter table public.vehicles rename column registration_expiry to date_expiry;

alter table public.vehicles
  drop column if exists make_model,
  drop column if exists body_type,
  drop column if exists or_number,
  drop column if exists cr_number,
  drop column if exists franchise_number,
  drop column if exists seat_configuration;

alter table public.vehicles
  add column if not exists case_number text,
  add column if not exists mv_file_number text,
  add column if not exists seat_type text
    check (seat_type is null or seat_type in ('2x2', '2x3')),
  add column if not exists aircon boolean,
  add column if not exists date_granted date;

drop function if exists public.request_vehicle_change(uuid, text, text, text, text, text, date, text, text, text, text, integer);

create or replace function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_case_number text,
  p_mv_file_number text,
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

revoke all on function public.request_vehicle_change(uuid, text, text, text, text, text, integer, text, boolean, date, date)
  from public, anon;
grant execute on function public.request_vehicle_change(uuid, text, text, text, text, text, integer, text, boolean, date, date)
  to authenticated;

notify pgrst, 'reload schema';
