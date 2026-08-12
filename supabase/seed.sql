-- Optional starter data: 20 bays named "Bay 1".."Bay 20".
-- Run after 0001_init.sql. Safe to edit the count/names before running, or
-- manage bays later from the PITX staff "Bays" page in the app.
insert into public.bays (name)
select 'Bay ' || i
from generate_series(1, 20) as i
on conflict (name) do nothing;
