-- Groups bays into gates, matching the terminal's actual gate layout, and
-- adds the bays named in that layout that didn't exist yet (only 20 bays
-- existed before this; the gate guide references bays up to 36).
--
-- Gate 2 (Bays 8-11)  - Laguna, Batangas, Quezon, Mindoro routes
-- Gate 4 (Bays 18-23) - Bicol, Visayas, Mindanao routes
-- Gate 5 (Bays 33-36) - North routes
--
-- Bays outside these ranges (1-7, 12-17, 24-32) aren't part of a named
-- gate in the guide provided, so they're left with gate = null - general-
-- purpose bays, not tied to a route category.
--
-- Run after 0019_vehicle_change_supporting_document.sql.

alter table public.bays
  add column if not exists gate text;

comment on column public.bays.gate is
  'Which terminal gate this bay belongs to (e.g. "Gate 2"), if any - used
   to suggest/restrict bay choices to the gate matching a booking''s route
   (see ROUTE_GATES in app.js). Null for general-purpose bays not tied to
   a specific gate.';

-- Bay 1-20 already exist (seed.sql) - just tag the ones inside a named
-- gate's range.
update public.bays set gate = 'Gate 2' where name in ('Bay 8', 'Bay 9', 'Bay 10', 'Bay 11');
update public.bays set gate = 'Gate 4' where name in ('Bay 18', 'Bay 19', 'Bay 20');

-- Bays 21-23 (rest of Gate 4) and 33-36 (Gate 5) didn't exist yet.
insert into public.bays (name, is_active, gate)
values
  ('Bay 21', true, 'Gate 4'),
  ('Bay 22', true, 'Gate 4'),
  ('Bay 23', true, 'Gate 4'),
  ('Bay 33', true, 'Gate 5'),
  ('Bay 34', true, 'Gate 5'),
  ('Bay 35', true, 'Gate 5'),
  ('Bay 36', true, 'Gate 5')
on conflict (name) do update set gate = excluded.gate;

notify pgrst, 'reload schema';
