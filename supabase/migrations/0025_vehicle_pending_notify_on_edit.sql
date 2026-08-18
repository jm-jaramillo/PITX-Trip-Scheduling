-- notify_vehicle_pending() (0024) only had an INSERT trigger, unlike its
-- bookings equivalent which also fires when an edit reverts an
-- already-decided row back to pending. Found while verifying #44 live:
-- editing an approved vehicle (request_vehicle_change) correctly reverts
-- it to pending, but staff never got notified there was something new to
-- review again.
--
-- Run after 0024_notifications.sql.

create or replace function public.notify_vehicle_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    insert into public.notifications (recipient_role, type, title, body, link, related_table, related_id)
    values (
      'staff',
      'vehicle_pending',
      'New vehicle registration',
      new.plate_no,
      'vehicle-approvals.html',
      'vehicles',
      new.id
    )
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger vehicles_notify_pending_update
  after update on public.vehicles
  for each row execute function public.notify_vehicle_pending();
