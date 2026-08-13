-- Vehicle registrations now need PITX staff approval, same shape as
-- bookings: pending -> approved/rejected, and any operator edit reverts an
-- approved vehicle back to pending (see request_vehicle_change() below,
-- mirroring request_booking_change() in 0002).
--
-- Run after 0004_vehicle_plate_normalization.sql.

alter table public.vehicles
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  add column if not exists rejection_reason text,
  add column if not exists decided_by uuid references public.profiles (id),
  add column if not exists decided_at timestamptz,
  add column if not exists revision_count integer not null default 0,
  add column if not exists previously_approved boolean not null default false;

comment on column public.vehicles.status is
  'Only approved vehicles are offered in the booking form''s plate number '
  'dropdown.';

create index if not exists vehicles_status_idx on public.vehicles (status);

-- ---------------------------------------------------------------------------
-- Replace the old unrestricted "operator can update their own vehicle"
-- policy: RLS is row-level, not column-level, so that policy would also let
-- an operator set status='approved' on their own row. All operator edits
-- now go through request_vehicle_change() instead; direct UPDATEs from
-- operators are no longer permitted (only staff's policy below allows one).
-- ---------------------------------------------------------------------------
drop policy if exists vehicles_update_own on public.vehicles;

drop policy if exists vehicles_staff_update on public.vehicles;
create policy vehicles_staff_update on public.vehicles
  for update
  using (public.is_staff())
  with check (public.is_staff());

-- Inserts must still start out pending - defence in depth alongside the
-- client always sending status: 'pending'.
drop policy if exists vehicles_insert_own on public.vehicles;
create policy vehicles_insert_own on public.vehicles
  for insert
  with check (operator_id = auth.uid() and status = 'pending');

create or replace function public.request_vehicle_change(
  p_vehicle_id uuid,
  p_plate_no text,
  p_make_model text,
  p_body_type text,
  p_or_number text,
  p_cr_number text,
  p_registration_expiry date
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

  v_was_approved := (v_status = 'approved');

  update public.vehicles set
    plate_no             = btrim(p_plate_no),
    make_model           = nullif(btrim(coalesce(p_make_model, '')), ''),
    body_type            = nullif(btrim(coalesce(p_body_type, '')), ''),
    or_number            = nullif(btrim(coalesce(p_or_number, '')), ''),
    cr_number            = nullif(btrim(coalesce(p_cr_number, '')), ''),
    registration_expiry  = p_registration_expiry,
    -- Back to the approval queue; an approved vehicle stops being offered
    -- in the booking dropdown until staff re-approve the edited details.
    status               = 'pending',
    rejection_reason      = null,
    decided_by            = null,
    decided_at            = null,
    previously_approved   = previously_approved or v_was_approved,
    revision_count        = revision_count + 1
  where id = p_vehicle_id;
end;
$$;

revoke all on function public.request_vehicle_change(uuid, text, text, text, text, text, date)
  from public, anon;
grant execute on function public.request_vehicle_change(uuid, text, text, text, text, text, date)
  to authenticated;

-- Mirrors bookings_mark_previously_approved from 0002: keeps
-- previously_approved accurate when staff approve through the normal
-- (plain UPDATE) path rather than through the function above.
create or replace function public.mark_vehicle_previously_approved()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'approved' then
    new.previously_approved := true;
  end if;
  return new;
end;
$$;

drop trigger if exists vehicles_mark_previously_approved on public.vehicles;
create trigger vehicles_mark_previously_approved
  before update on public.vehicles
  for each row
  execute function public.mark_vehicle_previously_approved();

notify pgrst, 'reload schema';
