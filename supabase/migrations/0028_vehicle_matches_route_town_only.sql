-- vehicle_matches_route() (0026) compared *full* route token sets, which
-- has the exact same bug just found and fixed in dashboard.html's own
-- client-side copy of this function: two different towns in the same
-- province ("Balanga, Bataan" vs "Mariveles, Bataan") match each other
-- purely on the shared province word "Bataan" - a vehicle registered
-- for Mariveles would incorrectly pass this check for a Balanga
-- booking. Since this function is what #51's actual enforcement relies
-- on (bookings_insert_own, request_booking_change()), this was a real
-- gap in the "must be registered for that specific route" requirement,
-- not just a cosmetic mismatch with the client.
--
-- Fixed the same way as the client: only compare the *town* segment
-- (text before the first comma) of each route, never the full string.
--
-- Run after 0027_vehicle_route_required_fix_shadowing.sql.

create or replace function public.route_town_part(p text)
returns text
language sql
immutable
as $$
  select case
    when position(',' in coalesce(p, '')) = 0 then coalesce(p, '')
    else substring(p from 1 for position(',' in p) - 1)
  end;
$$;

comment on function public.route_town_part(text) is
  'Text before the first comma in a route string - the town/municipality '
  'part, as opposed to the province after it. SQL port of dashboard.html''s '
  'routeTownPart(), kept in lockstep with it.';

create or replace function public.vehicle_matches_route(p_vehicle_route text, p_booking_route text)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from unnest(public.route_tokens(public.route_town_part(p_booking_route))) as bt
    where bt = any(public.route_tokens(public.route_town_part(p_vehicle_route)))
  );
$$;
