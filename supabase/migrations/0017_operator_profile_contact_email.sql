-- Adds contact email fields to operator_profiles, alongside the existing
-- contact name/number/position - the source data (a company-provided
-- operator database spreadsheet) includes real emails per contact, and
-- dropping them would lose real information the paper form doesn't ask
-- for but is genuinely useful to keep.
--
-- Run after 0016_transfer_recipient_vehicles.sql.

alter table public.operator_profiles
  add column if not exists contact1_email text,
  add column if not exists contact2_email text;

notify pgrst, 'reload schema';
