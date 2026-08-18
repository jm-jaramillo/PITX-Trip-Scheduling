-- route_tokens() stripped any character outside [A-Za-z0-9] - including
-- accented letters like the "ñ" in "Biñan" - via a single blanket
-- regexp_replace. That turns "BIÑAN" into "BI AN" (the "ñ" becomes a
-- bare space), leaving two 2-letter fragments that the length >= 3
-- filter then discards entirely: route_tokens('Biñan, Laguna') returns
-- zero tokens for the town part, so vehicle_matches_route('Biñan,
-- Laguna', 'Biñan, Laguna') returns false - a real Biñan-registered
-- vehicle is rejected by bookings_insert_own's RLS WITH CHECK (and
-- request_booking_change()) for a Biñan booking, unable to book the one
-- route it's actually meant for. Found via a live "no Biñan, Laguna in
-- Jam Liner" report - Jam Liner's vehicles were correctly linked to
-- "Biñan, Laguna" in the data (#54/#55), but the matching function
-- itself couldn't see it.
--
-- Fixed the same way as dashboard.html's routeTokens(): map each
-- accented letter to its base letter *before* the non-alphanumeric
-- strip, not silently discard it as if it carried no letter at all.
--
-- Run after 0028_vehicle_matches_route_town_only.sql.

create or replace function public.route_tokens(p text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    array_agg(w) filter (
      where length(w) >= 3
        and w not in ('CITY', 'VIA', 'THE', 'AND', 'OF', 'TUNNEL')
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
  'Significant words in a route string, filler words dropped, accented '
  'letters mapped to their base letter first (not discarded) - SQL port '
  'of dashboard.html''s routeTokens(), kept in lockstep with it.';
