-- "SAN"/"SANTA"/"SANTO" are generic Spanish-place-name honorifics shared
-- by many otherwise-unrelated towns - "Santa Cruz, Laguna" and "Santa
-- Rosa, Laguna" tokenize to {SANTA, CRUZ} and {SANTA, ROSA}, and since
-- "SANTA" wasn't a filtered stopword, the two sets overlapped on it,
-- making vehicle_matches_route('Santa Cruz, Laguna', 'Santa Rosa,
-- Laguna') return true - a vehicle only ever registered for Santa Cruz
-- passed as a match for Santa Rosa bookings too. Found via a live report:
-- an operator whose vehicles were all "Santa Cruz, Laguna" saw "Santa
-- Rosa, Laguna" offered in the Route dropdown despite having no vehicle
-- registered for it (#59).
--
-- Fixed the same way as the "CITY"/"VIA"/etc. filler words already
-- dropped: add SAN/SANTA/SANTO to the stopword list. Safe across all 91
-- routes in docs/assets/app.js's ROUTES - every "San "/"Santa "/"Santo "
-- route has a second, distinguishing word (Cruz, Rosa, Jose, Juan,
-- Andres, Pedro, Elena, Ana, Carlos...), so none of them collapse to
-- zero tokens once the honorific itself is filtered out.
--
-- (Pre-existing, unrelated to this fix: several distinct routes are
-- literally named "San Jose" in different provinces - Nueva Ecija,
-- Occidental Mindoro, Camarines Sur, Dinagat Islands - and always
-- collided with each other via the shared "JOSE" token, both before and
-- after this change, since route matching only compares the town part.
-- Not something this stopword fix causes or resolves.)
--
-- Run after 0029_route_tokens_diacritics.sql.

create or replace function public.route_tokens(p text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    array_agg(w) filter (
      where length(w) >= 3
        and w not in ('CITY', 'VIA', 'THE', 'AND', 'OF', 'TUNNEL', 'SAN', 'SANTA', 'SANTO')
    ),
    array[]::text[]
  )
  from unnest(
    regexp_split_to_array(
      regexp_replace(
        translate(upper(coalesce(p, '')), 'ÁÉÍÓÚÑÜ', 'AEIOUNU'),
        '[^A-Za-z0-9]', ' ', 'g'
      ),
      '\s+'
    )
  ) as w
  where w <> '';
$$;

comment on function public.route_tokens(text) is
  'Significant words in a route string, filler words and generic '
  'Spanish-place-name honorifics (SAN/SANTA/SANTO) dropped, accented '
  'letters mapped to their base letter first - SQL port of '
  'dashboard.html''s routeTokens(), kept in lockstep with it.';
