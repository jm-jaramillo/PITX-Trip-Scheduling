-- Trip numbers, similar to an airline flight number: the first 3 letters
-- of the route's town name, then the booking's time as 24-hour HHMM -
-- e.g. Naga City, Camarines Sur at 3:30 PM is "NAG1530". Assigned
-- automatically the moment a booking is approved, not before (a pending
-- request's route/plate/time can still change, so there's nothing
-- stable to name yet).
--
-- Run after 0032_transfer_recipient_route_match.sql.

alter table public.bookings add column if not exists trip_number text;

comment on column public.bookings.trip_number is
  'Auto-assigned on approval - <3-letter route code><HHMM>, e.g. '
  'NAG1530 for Naga City, Camarines Sur at 3:30 PM. Cleared whenever a '
  'booking leaves approved status (see assign_trip_number()) so it''s '
  'always recomputed fresh against whatever route/time is current when '
  'it''s next approved, never stale.';

-- One 3-letter code per canonical route (docs/assets/app.js's ROUTES).
-- Usually the first 3 letters of the town's first word - "Naga City,
-- Camarines Sur" -> NAG - but wherever two routes would collide on that
-- (e.g. "Santa Rosa, Laguna" and "Santa Cruz, Laguna" both starting
-- "SAN"/"STA"), the second word is used instead (ROS / CRU). A handful
-- of single-word towns that still collide even so (e.g. "Baguio" and
-- "Bagamanoc" both "BAG"), plus "San Jose" being the literal name of 4
-- routes in different provinces, needed a manual override - see the
-- comment above each such row below. Keep this table in sync with
-- ROUTES: adding a route there means adding its code here too, checked
-- against every existing code for a collision first.
create table if not exists public.route_trip_codes (
  route text primary key,
  code text not null unique
);

insert into public.route_trip_codes (route, code) values
  ('Baguio City, Benguet', 'BAG'),
  ('Lagangilang, Abra', 'LAG'),
  ('Banaue, Ifugao', 'BAN'),
  ('San Carlos City, Pangasinan', 'CAR'),
  ('Dagupan City, Pangasinan', 'DAG'),
  ('Laoag City, Ilocos Norte', 'LAO'),
  ('Tuguegarao City, Cagayan', 'TUG'),
  ('Santa Ana, Cagayan', 'ANA'),
  ('Olongapo City, Zambales', 'OLO'),
  ('Balanga City, Bataan', 'BAL'),
  ('Mariveles, Bataan', 'MAR'),
  ('Mabalacat City, Pampanga', 'MAB'),
  -- "San Jose" is the literal name of 4 different routes (Nueva Ecija,
  -- Occidental Mindoro, Camarines Sur, Dinagat Islands) - no amount of
  -- picking a different word within the town name can distinguish them,
  -- so these four borrow a letter from their province instead.
  ('San Jose City, Nueva Ecija', 'JSN'),
  ('Alfonso, Cavite', 'ALF'),
  ('Ternate, Cavite', 'TER'),
  ('Mendez, Cavite', 'MEN'),
  ('Maragondon, Cavite', 'MRG'), -- collides with Mariveles, Bataan on "MAR"
  ('Balayan, Batangas', 'BLY'), -- collides with Balanga City/Balatan on "BAL"
  ('Batangas City, Batangas', 'BAT'),
  ('Calatagan, Batangas', 'CAL'),
  ('Lemery, Batangas', 'LEM'),
  ('Lipa City, Batangas', 'LIP'),
  ('Nasugbu, Batangas', 'NAS'),
  ('San Juan, Batangas', 'JUA'),
  ('Bauan, Batangas', 'BAU'),
  ('Santa Cruz, Laguna', 'CRU'), -- "STA" collides with Santa Rosa/Elena/Ana - use 2nd word
  ('San Pedro, Laguna', 'PED'),
  ('Biñan, Laguna', 'BIN'), -- ASCII only, diacritic stripped for the code itself
  ('Santa Rosa, Laguna', 'ROS'), -- "STA" collides with Santa Cruz/Elena/Ana - use 2nd word
  ('Calauag, Quezon', 'CLG'), -- collides with Calatagan/Calbayog on "CAL"
  ('Guinayangan, Quezon', 'GUI'),
  ('Lucena City, Quezon', 'LUC'),
  ('San Andres, Quezon', 'AND'),
  ('Tagkawayan, Quezon', 'TAG'),
  ('San Jose, Occidental Mindoro', 'JSO'),
  ('Boac, Marinduque', 'BOA'),
  ('Legazpi City, Albay', 'LEG'),
  ('Pio Duran, Albay', 'PIO'),
  ('Tabaco City, Albay', 'TAB'),
  ('Tiwi, Albay', 'TIW'),
  ('Daet, Camarines Norte', 'DAE'),
  ('Jose Panganiban, Camarines Norte', 'PAN'), -- uses its own 2nd word, not "JOS"
  ('Paracale, Camarines Norte', 'PAR'),
  ('Santa Elena, Camarines Norte', 'ELE'), -- "STA" collides - use 2nd word
  ('Balatan, Camarines Sur', 'BLT'), -- collides with Balanga City/Balayan on "BAL"
  ('Buhi, Camarines Sur', 'BUH'),
  ('Iriga City, Camarines Sur', 'IRI'),
  ('Lagonoy, Camarines Sur', 'LGN'), -- collides with Lagangilang, Abra on "LAG"
  ('Naga City, Camarines Sur', 'NAG'),
  ('San Jose, Camarines Sur', 'JSC'),
  ('Caramoan, Camarines Sur', 'CRM'), -- collides with San Carlos City on "CAR"
  ('Pasacao, Camarines Sur', 'PAS'),
  ('Presentacion, Camarines Sur', 'PRE'),
  ('Garchitorena, Camarines Sur', 'GAR'),
  ('Bagamanoc, Catanduanes', 'BGM'), -- collides with Baguio City, Benguet on "BAG"
  ('Baras, Catanduanes', 'BAR'),
  ('Viga, Catanduanes', 'VIG'),
  ('Virac, Catanduanes', 'VIR'),
  ('Bulan, Sorsogon', 'BUL'),
  ('Gubat, Sorsogon', 'GUB'),
  ('Magallanes, Sorsogon', 'MAG'),
  ('Matnog, Sorsogon', 'MAT'),
  ('Pilar, Sorsogon', 'PIL'),
  ('Sorsogon City, Sorsogon', 'SOR'),
  ('Donsol, Sorsogon', 'DON'),
  ('Prieto Diaz, Sorsogon', 'PRI'),
  ('Masbate City, Masbate', 'MAS'),
  ('Placer, Masbate', 'PLA'),
  ('Mandaon, Masbate', 'MAN'),
  ('Iloilo City, Iloilo', 'ILO'),
  ('Cebu City, Cebu', 'CEB'),
  ('Tagbilaran City, Bohol', 'TGB'), -- collides with Tagkawayan/Tagum on "TAG"
  ('Borongan City, Eastern Samar', 'BOR'),
  ('Oras, Eastern Samar', 'ORA'),
  ('Guiuan, Eastern Samar', 'GUA'), -- collides with Guinayangan, Quezon on "GUI"
  ('Ormoc City, Leyte', 'ORM'),
  ('Palompon, Leyte', 'PAL'),
  ('Tacloban City, Leyte', 'TAC'),
  ('Catarman, Northern Samar', 'CAT'),
  ('Laoang, Northern Samar', 'LNG'), -- collides with Laoag City, Ilocos Norte on "LAO"
  ('Calbayog City, Samar', 'CBY'), -- collides with Calatagan/Calauag on "CAL"
  ('Liloan, Southern Leyte', 'LIL'),
  ('Maasin City, Southern Leyte', 'MAA'),
  ('Silago, Southern Leyte', 'SIL'),
  ('Cagayan de Oro City, Misamis Oriental', 'CAG'),
  ('Davao City, Davao del Sur', 'DAV'),
  ('Tagum City, Davao del Norte', 'TGM'), -- collides with Tagkawayan/Tagbilaran on "TAG"
  ('General Santos City, South Cotabato', 'GEN'),
  ('San Jose, Dinagat Islands', 'JSD'),
  ('Butuan City, Agusan del Norte', 'BUT'),
  ('Muntinlupa City, Metro Manila', 'MUN')
on conflict (route) do update set code = excluded.code;

grant select on public.route_trip_codes to authenticated;

-- Computes a booking's trip number: <code><HHMM>, plus a lettered
-- suffix (A, B, C...) if this isn't the first approved booking sharing
-- the same date/route/slot - multiple bays can serve the same route at
-- the same time, so the base code alone isn't always unique per day,
-- same as an airline running extra sections of one flight number.
-- Falls back to the first 3 letters of the route itself (uppercased,
-- non-letters stripped, right-padded with X) for a route that isn't in
-- route_trip_codes - a stale/free-text route from before the canonical
-- list existed, so trip numbering never hard-fails on old data.
create or replace function public.compute_trip_number(
  p_route text, p_slot smallint, p_booking_date date, p_exclude_booking_id uuid
)
returns text
language plpgsql
stable
as $$
declare
  v_code text;
  v_hour int;
  v_minute int;
  v_base text;
  v_suffix_count int;
begin
  select code into v_code from public.route_trip_codes where route = p_route;
  if v_code is null then
    v_code := rpad(
      upper(regexp_replace(coalesce(p_route, ''), '[^A-Za-z]', '', 'g')),
      3, 'X'
    );
    v_code := left(v_code, 3);
  end if;

  v_hour := (p_slot * 30) / 60;
  v_minute := (p_slot * 30) % 60;
  v_base := v_code || lpad(v_hour::text, 2, '0') || lpad(v_minute::text, 2, '0');

  select count(*) into v_suffix_count
  from public.bookings
  where booking_date = p_booking_date
    and route = p_route
    and slot = p_slot
    and status = 'approved'
    and trip_number is not null
    and id <> p_exclude_booking_id;

  return v_base || case when v_suffix_count = 0 then '' else chr(64 + v_suffix_count) end;
end;
$$;

-- Assigns a trip number the moment a booking becomes approved, and
-- clears it the moment a booking leaves approved status (e.g.
-- request_booking_change() sending it back to pending for
-- re-approval) - so a booking never carries a trip number describing a
-- route/time it no longer has, and always gets a fresh one computed
-- against whatever's current when it's next approved. A bay
-- reassignment (status staying 'approved' throughout, per
-- schedule.html) touches neither branch, leaving an existing trip
-- number untouched, since a trip number describes the route/time, not
-- the bay.
create or replace function public.assign_trip_number()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.trip_number := public.compute_trip_number(new.route, new.slot, new.booking_date, new.id);
  elsif new.status is distinct from 'approved' then
    new.trip_number := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_assign_trip_number on public.bookings;
create trigger trg_assign_trip_number
  before update on public.bookings
  for each row
  execute function public.assign_trip_number();

notify pgrst, 'reload schema';
