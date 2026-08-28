-- checkSlotOccupancy() (dashboard.html) needs to show an operator every
-- OTHER operator's live booking for a given date - including still-
-- pending ones, since two operators requesting the same destination/time
-- is exactly the case worth flagging before either is approved. Raw
-- table access can't do this: bookings_select (0001, widened by 0040)
-- only ever exposes a pending row to its own operator or to staff -
-- correctly, a pending request is still private. Rather than widen that
-- policy (which would let any operator browse the full detail of every
-- other pending request), this adds a narrow, read-only RPC that returns
-- just the fields the occupancy check actually needs.
create or replace function public.list_bookings_for_date(p_date date)
returns table (
  slot smallint,
  route text,
  operator_name text,
  trade_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select b.slot, b.route, b.operator_name, b.trade_name
  from public.bookings b
  where b.booking_date = p_date
    and b.status in ('pending', 'approved')
    and b.operator_id <> auth.uid();
$$;

revoke all on function public.list_bookings_for_date(date) from public, anon;
grant execute on function public.list_bookings_for_date(date) to authenticated;

notify pgrst, 'reload schema';
