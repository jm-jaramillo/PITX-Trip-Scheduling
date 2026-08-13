-- Operator vehicle registration: scan an OR/CR photo (extracted client-side
-- via Tesseract.js, no server OCR cost) or enter details manually. Either
-- way the operator can edit every field afterward.
--
-- Run this after 0001_init.sql and 0002_booking_changes.sql.

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.profiles (id) on delete cascade,
  plate_no text not null,
  make_model text,
  body_type text,
  or_number text,
  cr_number text,
  registration_expiry date,
  -- Path within the vehicle-docs storage bucket, e.g. "<operator_id>/<uuid>.jpg".
  -- Null for manually-entered vehicles with no photo attached.
  photo_path text,
  source text not null default 'manual' check (source in ('scanned', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.vehicles.source is
  'How this row was first created - scanned (OCR from an OR/CR photo, then '
  'reviewed) or manual. Editable afterward either way.';

-- Guards against accidentally registering the same plate twice; case-
-- insensitive since plates get typed inconsistently ("abc1234" vs "ABC 1234").
create unique index if not exists vehicles_operator_plate_unique
  on public.vehicles (operator_id, upper(plate_no));

create index if not exists vehicles_operator_id_idx
  on public.vehicles (operator_id);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists vehicles_touch_updated_at on public.vehicles;
create trigger vehicles_touch_updated_at
  before update on public.vehicles
  for each row
  execute function public.touch_updated_at();

alter table public.vehicles enable row level security;

drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles
  for select
  using (operator_id = auth.uid() or public.is_staff());

drop policy if exists vehicles_insert_own on public.vehicles;
create policy vehicles_insert_own on public.vehicles
  for insert
  with check (operator_id = auth.uid());

drop policy if exists vehicles_update_own on public.vehicles;
create policy vehicles_update_own on public.vehicles
  for update
  using (operator_id = auth.uid())
  with check (operator_id = auth.uid());

drop policy if exists vehicles_delete_own on public.vehicles;
create policy vehicles_delete_own on public.vehicles
  for delete
  using (operator_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage: private bucket for OR/CR photos. Path convention is
-- "<operator_id>/<file>", so storage.foldername(name)[1] is the owning
-- operator's auth uid - that's what the policies below check.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('vehicle-docs', 'vehicle-docs', false)
on conflict (id) do nothing;

drop policy if exists vehicle_docs_select on storage.objects;
create policy vehicle_docs_select on storage.objects
  for select
  using (
    bucket_id = 'vehicle-docs'
    and (auth.uid()::text = (storage.foldername(name))[1] or public.is_staff())
  );

drop policy if exists vehicle_docs_insert on storage.objects;
create policy vehicle_docs_insert on storage.objects
  for insert
  with check (
    bucket_id = 'vehicle-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists vehicle_docs_update on storage.objects;
create policy vehicle_docs_update on storage.objects
  for update
  using (
    bucket_id = 'vehicle-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists vehicle_docs_delete on storage.objects;
create policy vehicle_docs_delete on storage.objects
  for delete
  using (
    bucket_id = 'vehicle-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

notify pgrst, 'reload schema';
