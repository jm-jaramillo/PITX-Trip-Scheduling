-- PITX bus bay hourly booking - initial schema
-- Run this once in your Supabase project's SQL Editor (or via the Supabase
-- CLI). See README.md for the full setup walkthrough.

-- ---------------------------------------------------------------------------
-- profiles: one row per Supabase Auth user, mirrors app_metadata.role
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  role text not null check (role in ('operator', 'staff')),
  operator_name text,
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per login account. role + username mirror the auth user''s '
  'app_metadata, set only via the service-role Admin API at account '
  'creation time.';

-- ---------------------------------------------------------------------------
-- bays: the physical bus bays operators are assigned into on approval
-- ---------------------------------------------------------------------------
create table if not exists public.bays (
  id bigint generated always as identity primary key,
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- bookings: one hourly slot request from an operator
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.profiles (id),
  operator_name text not null,
  route text not null,
  plate_no text not null,
  booking_date date not null,
  hour smallint not null check (hour between 0 and 23),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  assigned_bay_id bigint references public.bays (id),
  rejection_reason text,
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

comment on column public.bookings.assigned_bay_id is
  'Set by PITX staff when a request is approved. Operators do not pick '
  'a bay themselves.';

create index if not exists bookings_date_hour_status_idx
  on public.bookings (booking_date, hour, status);

create index if not exists bookings_operator_id_idx
  on public.bookings (operator_id);

-- A bay can only be approved for one booking in a given hour.
create unique index if not exists bookings_unique_approved_bay_slot
  on public.bookings (booking_date, hour, assigned_bay_id)
  where (status = 'approved' and assigned_bay_id is not null);

-- ---------------------------------------------------------------------------
-- Helper: is the current auth user PITX staff?
-- security definer + fixed search_path so it can read profiles regardless
-- of the caller's RLS visibility, without being hijacked by a mutable
-- search_path.
-- ---------------------------------------------------------------------------
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'staff'
  );
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.bays enable row level security;
alter table public.bookings enable row level security;

-- profiles: everyone can read their own row; staff can read everyone's.
-- Inserts/updates only ever happen via the service-role Admin API
-- (bypasses RLS), so there are intentionally no write policies here.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select
  using (id = auth.uid() or public.is_staff());

-- bays: any signed-in user can see the active bay list (staff need it to
-- assign a bay on approval); only staff can manage the list.
drop policy if exists bays_select on public.bays;
create policy bays_select on public.bays
  for select
  using (auth.uid() is not null);

drop policy if exists bays_staff_write on public.bays;
create policy bays_staff_write on public.bays
  for all
  using (public.is_staff())
  with check (public.is_staff());

-- bookings: operators see + create their own; staff see + manage all.
drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select
  using (operator_id = auth.uid() or public.is_staff());

drop policy if exists bookings_insert_own on public.bookings;
create policy bookings_insert_own on public.bookings
  for insert
  with check (operator_id = auth.uid() and status = 'pending');

drop policy if exists bookings_staff_update on public.bookings;
create policy bookings_staff_update on public.bookings
  for update
  using (public.is_staff())
  with check (public.is_staff());

-- operators may only cancel their own still-pending request.
drop policy if exists bookings_cancel_own on public.bookings;
create policy bookings_cancel_own on public.bookings
  for update
  using (operator_id = auth.uid() and status = 'pending')
  with check (operator_id = auth.uid() and status = 'cancelled');
