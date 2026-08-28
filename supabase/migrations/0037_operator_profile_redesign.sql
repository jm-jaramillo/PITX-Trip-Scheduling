-- Reworks operator_profiles per the updated intake form:
--   - Removes TIN No., Serial Number (OR), and NAU - no longer collected.
--   - Adds Trade Name, Operator/Trade Code, and a logo upload (stored in
--     a new private 'operator-docs' bucket, same pattern as
--     vehicle-docs for vehicle documents).
--   - Replaces the fixed contact1_*/contact2_* column pairs with a
--     single `contacts` JSONB array (up to 5 entries: name, position,
--     number, email) - the form now has an "+ Add contact" button
--     instead of two hardcoded contact-person sections, so the number
--     of contacts is no longer fixed at exactly two.
--   - "Company name" is relabeled "Operator" on the form; the
--     underlying column stays `company_name` (an actual rename would
--     collide in meaning with profiles.operator_name, a different
--     column on a different table - relabeling avoids that confusion
--     without an unnecessary schema break).
--
-- Existing contact1_*/contact2_* data is folded into the new `contacts`
-- array before the old columns are dropped, so no real contact
-- information already on file is lost by this change.
--
-- Run after 0036_vehicle_trade_name.sql.

alter table public.operator_profiles
  add column if not exists trade_name text,
  add column if not exists operator_code text,
  add column if not exists logo_path text,
  add column if not exists contacts jsonb not null default '[]'::jsonb;

comment on column public.operator_profiles.trade_name is
  'Optional DBA/trade name for this operator account as a whole - '
  'distinct from vehicles.trade_name, which is per-vehicle for '
  'operators running more than one trade.';
comment on column public.operator_profiles.operator_code is
  'Operator/Trade Code - an internal PITX reference code, free text.';
comment on column public.operator_profiles.logo_path is
  'Storage path (operator-docs bucket) of this operator''s uploaded '
  'logo/profile picture.';
comment on column public.operator_profiles.contacts is
  'Up to 5 contact persons, each {name, position, number, email} - '
  'replaces the old fixed contact1_*/contact2_* column pairs so the '
  'form can offer an "Add contact" button instead of exactly two '
  'hardcoded sections.';

alter table public.operator_profiles
  drop constraint if exists operator_profiles_contacts_max_five;
alter table public.operator_profiles
  add constraint operator_profiles_contacts_max_five
    check (jsonb_typeof(contacts) = 'array' and jsonb_array_length(contacts) <= 5);

-- Folds any existing contact1_*/contact2_* data into the new array
-- before those columns are dropped - a contact slot is only included
-- if it has a name (matching the old form's own "at least a name"
-- expectation), so a row where only, say, contact2_email was ever
-- filled in doesn't produce a nameless ghost entry.
update public.operator_profiles
set contacts = (
  select coalesce(jsonb_agg(c), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'name', contact1_name, 'position', contact1_position,
      'number', contact1_number, 'email', contact1_email
    ) as c
    where contact1_name is not null and btrim(contact1_name) <> ''
    union all
    select jsonb_build_object(
      'name', contact2_name, 'position', contact2_position,
      'number', contact2_number, 'email', contact2_email
    )
    where contact2_name is not null and btrim(contact2_name) <> ''
  ) as contact_rows
)
where jsonb_array_length(contacts) = 0;

alter table public.operator_profiles
  drop column if exists tin_no,
  drop column if exists or_serial_number,
  drop column if exists nau,
  drop column if exists contact1_name,
  drop column if exists contact1_position,
  drop column if exists contact1_number,
  drop column if exists contact1_email,
  drop column if exists contact2_name,
  drop column if exists contact2_position,
  drop column if exists contact2_number,
  drop column if exists contact2_email;

-- ---------------------------------------------------------------------------
-- Storage: private bucket for operator logos, same convention as
-- vehicle-docs ("<operator_id>/<file>", so storage.foldername(name)[1]
-- is the owning operator's auth uid).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('operator-docs', 'operator-docs', false)
on conflict (id) do nothing;

drop policy if exists operator_docs_select on storage.objects;
create policy operator_docs_select on storage.objects
  for select
  using (
    bucket_id = 'operator-docs'
    and (auth.uid()::text = (storage.foldername(name))[1] or public.is_staff())
  );

drop policy if exists operator_docs_insert on storage.objects;
create policy operator_docs_insert on storage.objects
  for insert
  with check (
    bucket_id = 'operator-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists operator_docs_update on storage.objects;
create policy operator_docs_update on storage.objects
  for update
  using (
    bucket_id = 'operator-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists operator_docs_delete on storage.objects;
create policy operator_docs_delete on storage.objects
  for delete
  using (
    bucket_id = 'operator-docs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

notify pgrst, 'reload schema';
