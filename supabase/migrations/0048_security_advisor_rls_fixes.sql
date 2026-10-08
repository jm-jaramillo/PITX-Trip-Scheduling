-- Fixes the two "RLS Disabled in Public" errors from Supabase's Security
-- Advisor: public.route_trip_codes and public._schema_migrations are both
-- reachable through PostgREST but had no row level security, so any role
-- granted access to them (or, for _schema_migrations, any role at all,
-- since it was never explicitly revoked from PUBLIC) could read/write them
-- directly instead of only through the app.

-- route_trip_codes: static route -> trip-code lookup table (0033), already
-- select-granted to authenticated. Add RLS with a matching read-only
-- policy - it's reference data, not writable through the API.
alter table public.route_trip_codes enable row level security;

drop policy if exists route_trip_codes_select on public.route_trip_codes;
create policy route_trip_codes_select on public.route_trip_codes
  for select
  using (auth.uid() is not null);

-- _schema_migrations: bookkeeping table for scripts/run-migration.mjs
-- (tracks which migration files have been applied against DATABASE_URL).
-- It's an internal deploy-tooling ledger, not app data - no one should
-- read or write it through the client API at all, so enable RLS with no
-- policies (deny-all to anon/authenticated; the migration script itself
-- connects with the DB owner role, which bypasses RLS as usual).
alter table public._schema_migrations enable row level security;

revoke all on public._schema_migrations from anon, authenticated;
