-- Lets an operator attach a supporting document to a vehicle registration
-- (LTFRB franchise/CPC, insurance, etc.) - separate from photo_path, which
-- is specifically the OR/CR photo used for OCR scanning. Staff can view
-- whichever of these were uploaded when reviewing a registration.
--
-- Reuses the existing vehicle-docs bucket and its storage policies
-- (migration 0003) unchanged - they're keyed on the operator_id folder
-- prefix, not the file itself, so any file an operator uploads under
-- their own folder is already covered.
--
-- Run after 0017_operator_profile_contact_email.sql.

alter table public.vehicles
  add column if not exists supporting_doc_path text,
  add column if not exists supporting_doc_name text;

comment on column public.vehicles.supporting_doc_path is
  'Path within the vehicle-docs storage bucket to a supporting document
   (franchise/CPC, insurance, etc.), e.g. "<operator_id>/<uuid>.pdf". Null
   if none uploaded.';

comment on column public.vehicles.supporting_doc_name is
  'Original filename of the supporting document, shown in the UI instead
   of the opaque storage path.';

notify pgrst, 'reload schema';
