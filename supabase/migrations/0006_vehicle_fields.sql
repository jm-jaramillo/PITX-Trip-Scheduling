-- Adds franchise number, route, body number, seat configuration, and seat
-- count to vehicle registration.
--
-- request_vehicle_change()'s signature changes (new parameters), so it must
-- be dropped and recreated rather than CREATE OR REPLACE'd - Postgres
-- doesn't allow changing a function's parameter list in place.
--
-- Run after 0005_vehicle_approvals.sql.

alter table public.vehicles
  add column if not exists franchise_number text,
  add column if not exists route text,
  add column if not exists body_number text,
  add column if not exists seat_configuration text,
  add column if not exists seat_count integer check (seat_count is null or seat_count > 0);

drop function if exists public.request_vehicle_change(uuid, text, text, text, text, text, date);

create or replace function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_make_model text,
  p_body_type text,
  p_or_number text,
  p_cr_number text,
  p_registration_expiry date,
  p_franchise_number text,
  p_route text,
  p_body_number text,
  p_seat_configuration text,
  p_seat_count integer
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
  if p_seat_count is not null and p_seat_count <= 0 then
    raise exception 'Number of seats must be positive.';
  end if;

  v_was_approved := (v_status = 'approved');

  update public.vehicles set
    plate_no             = btrim(p_plate_no),
    make_model           = nullif(btrim(coalesce(p_make_model, '')), ''),
    body_type            = nullif(btrim(coalesce(p_body_type, '')), ''),
    or_number            = nullif(btrim(coalesce(p_or_number, '')), ''),
    cr_number            = nullif(btrim(coalesce(p_cr_number, '')), ''),
    registration_expiry  = p_registration_expiry,
    franchise_number     = nullif(btrim(coalesce(p_franchise_number, '')), ''),
    route                = nullif(btrim(coalesce(p_route, '')), ''),
    body_number          = nullif(btrim(coalesce(p_body_number, '')), ''),
    seat_configuration   = nullif(btrim(coalesce(p_seat_configuration, '')), ''),
    seat_count           = p_seat_count,
    status               = 'pending',
    rejection_reason      = null,
    decided_by            = null,
    decided_at            = null,
    previously_approved   = previously_approved or v_was_approved,
    revision_count        = revision_count + 1
  where id = p_vehicle_id;
end;
$$;

revoke all on function public.request_vehicle_change(uuid, text, text, text, text, text, date, text, text, text, text, integer)
  from public, anon;
grant execute on function public.request_vehicle_change(uuid, text, text, text, text, text, date, text, text, text, text, integer)
  to authenticated;

notify pgrst, 'reload schema';
