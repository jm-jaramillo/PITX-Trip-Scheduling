-- expire_stale_pending_bookings() (migration 0045) is SECURITY DEFINER
-- and granted to `authenticated`, but never checked that the caller is
-- staff. Any signed-in operator could therefore invoke it directly and
-- mass-reject *every* operator's past-dated pending requests - writing
-- to rows RLS otherwise never lets them touch.
--
-- The blast radius was small (it only ever touches bookings whose date
-- has already passed, which can't be fulfilled either way, and it sets
-- the same status a staff member would) which is why nothing surfaced
-- in use. It's still an operator writing to other operators' rows, so
-- it gets the same guard every other staff-only routine here has.
--
-- app.js already only calls this when profile.role === 'staff', so this
-- narrows the RPC to what the client was doing anyway. Found while
-- auditing console errors during the #90 end-to-end test.
create or replace function public.expire_stale_pending_bookings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.is_staff() then
    raise exception 'Only staff can expire stale pending requests.';
  end if;

  update public.bookings set
    status           = 'rejected',
    rejection_reason = 'Automatically closed - the scheduled date passed while this request was still awaiting review.',
    decided_at       = now()
  where status = 'pending'
    and booking_date < (now() at time zone 'Asia/Manila')::date;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

notify pgrst, 'reload schema';
