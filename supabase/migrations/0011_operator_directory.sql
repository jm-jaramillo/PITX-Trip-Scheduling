-- A minimal, read-only operator directory so the transfer dialog can offer
-- a dropdown of real operator accounts instead of a free-text username.
-- Deliberately narrow: only username + operator_name (nothing an operator
-- couldn't already see printed on the other company's own bus), not the
-- full profiles row - RLS still only lets an operator read their own
-- profiles row directly.
--
-- Run after 0010_booking_transfers.sql.

create or replace function public.list_operator_accounts()
returns table (username text, operator_name text)
language sql
security definer
set search_path = public
stable
as $$
  select username, operator_name
  from public.profiles
  where role = 'operator' and id <> auth.uid()
  order by coalesce(operator_name, username);
$$;

revoke all on function public.list_operator_accounts() from public, anon;
grant execute on function public.list_operator_accounts() to authenticated;

notify pgrst, 'reload schema';
