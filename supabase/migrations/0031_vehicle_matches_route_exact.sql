-- Restart of the vehicle-route matching rule (#60): now that the #58
-- rebuild makes `vehicles.route` hold the *exact* canonical route string
-- from docs/assets/app.js's ROUTES (verified: 1,778 of 1,832 vehicles
-- match one exactly, and every operator with approved vehicles has at
-- least one exact match), the word-token fuzzy matching this function
-- has done since #48 is no longer needed - and it was the root cause of
-- three separate bugs found in production (#56 diacritics, #59 SAN/
-- SANTA/SANTO collisions, plus the original town-vs-province mixup fixed
-- in #51). Word-overlap matching over free text made sense when
-- `vehicles.route` was still an unlinked franchise sentence; it doesn't
-- once the data itself is the canonical string.
--
-- vehicle_matches_route() is simplified to plain equality.
-- route_tokens()/route_town_part() (migrations 0026/0028/0029/0030) have
-- no other callers (checked across every migration file) and are
-- dropped rather than left as dead code.
--
-- Run after 0030_route_tokens_san_santa_stopwords.sql.

create or replace function public.vehicle_matches_route(p_vehicle_route text, p_booking_route text)
returns boolean
language sql
immutable
as $$
  select p_vehicle_route is not distinct from p_booking_route
     and p_vehicle_route is not null;
$$;

comment on function public.vehicle_matches_route(text, text) is
  'Whether a vehicle is registered for a booking''s route - plain '
  'equality now that vehicles.route holds the exact canonical route '
  'string (see #58''s masterlist-derived rebuild of ROUTES). SQL port of '
  'dashboard.html''s vehicleMatchesRoute(), kept in lockstep with it.';

drop function if exists public.route_tokens(text);
drop function if exists public.route_town_part(text);
