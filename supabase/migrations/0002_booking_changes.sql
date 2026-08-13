-- Lets operators modify a booking, with every change re-entering the PITX
-- staff approval queue.
--
-- Behaviour (see README "Modifying a booking"):
--   pending  -> edited values, stays pending
--   approved -> edited values, reverts to pending and RELEASES the bay
--
-- Run this after 0001_init.sql.

-- ---------------------------------------------------------------------------
-- Track edit history so staff can tell a re-approval from a fresh request
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists revision_count integer not null default 0,
  add column if not exists last_edited_at timestamptz,
  add column if not exists previously_approved boolean not null default false;

comment on column public.bookings.previously_approved is
  'True once this booking has been approved at least once. A pending row '
  'with this set is a re-approval of a slot the operator already held.';

-- ---------------------------------------------------------------------------
-- request_booking_change: the only way an operator may edit a booking.
--
-- Runs as SECURITY DEFINER because Postgres RLS is row-level, not
-- column-level: a plain UPDATE policy permissive enough to allow editing
-- would also let an operator write `assigned_bay_id` and hand themselves a
-- bay. Routing edits through this function means the operator can only ever
-- change the four fields below, and the status/bay transition is decided
-- here rather than by the client.
-- ---------------------------------------------------------------------------
create or replace function public.request_booking_change(
  p_booking_id uuid,
  p_route text,
  p_plate_no text,
  p_booking_date date,
  p_hour smallint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_was_approved boolean;
  -- PITX runs on Philippine time; comparing against UTC's current_date would
  -- wrongly reject same-day bookings made after 4pm local.
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  select status into v_status
  from public.bookings
  where id = p_booking_id and operator_id = auth.uid()
  for update;

  if v_status is null then
    raise exception 'Booking not found.';
  end if;
  if v_status not in ('pending', 'approved') then
    raise exception
      'Only pending or approved bookings can be changed. Submit a new request instead.';
  end if;

  if coalesce(btrim(p_route), '') = '' then
    raise exception 'Route is required.';
  end if;
  if coalesce(btrim(p_plate_no), '') = '' then
    raise exception 'Plate number is required.';
  end if;
  if p_hour is null or p_hour < 0 or p_hour > 23 then
    raise exception 'Hour must be between 0 and 23.';
  end if;
  if p_booking_date is null or p_booking_date < v_today then
    raise exception 'Booking date cannot be in the past.';
  end if;

  v_was_approved := (v_status = 'approved');

  update public.bookings set
    route               = btrim(p_route),
    plate_no            = btrim(p_plate_no),
    booking_date        = p_booking_date,
    hour                = p_hour,
    -- Back to the queue; the previously held bay is released so another
    -- operator can be approved into it while this change is reviewed.
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

revoke all on function public.request_booking_change(uuid, text, text, date, smallint)
  from public, anon;
grant execute on function public.request_booking_change(uuid, text, text, date, smallint)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Keep previously_approved accurate when staff approve through the normal
-- path (a plain UPDATE from the staff UI, not this function).
-- ---------------------------------------------------------------------------
create or replace function public.mark_previously_approved()
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

drop trigger if exists bookings_mark_previously_approved on public.bookings;
create trigger bookings_mark_previously_approved
  before update on public.bookings
  for each row
  execute function public.mark_previously_approved();

-- ---------------------------------------------------------------------------
-- Tell PostgREST to re-read the schema. Without this the API keeps serving a
-- cached catalogue that predates request_booking_change() and rejects calls
-- to it with "permission denied for function", even though the grant above
-- is correct. Harmless to run more than once.
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';
