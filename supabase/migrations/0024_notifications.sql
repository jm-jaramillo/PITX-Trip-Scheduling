-- Notification panel, both roles: staff get notified of new booking/
-- vehicle/transfer requests to review; operators get notified when their
-- own booking/vehicle/transfer gets decided; both get notified when a
-- vehicle's CPC or OR/CR is within 30 days of its validity date.
--
-- Design notes:
--   * `recipient_id` is null for a staff broadcast (any pending request
--     is everyone's to review, not one staff member's) - never null for
--     an operator notification, which always targets one account.
--   * No client INSERT policy exists on purpose - every row is written by
--     a SECURITY DEFINER trigger/function below, never directly by the
--     browser client.
--   * Marking a *broadcast* staff notification read marks it read for
--     every staff member, not just whoever clicked it first - there's no
--     per-staff-member read table. Acceptable for a small ops team; would
--     need a separate join table to do this precisely per-recipient.
--   * The expiry check (CPC/OR-CR within 30 days) isn't event-driven like
--     the others - nothing "happens" when a date gets closer. It's synced
--     by `sync_expiry_notifications()`, called from the client on every
--     nav render (see app.js) rather than a cron job, since this app has
--     no scheduled server-side execution. It's idempotent (ON CONFLICT DO
--     NOTHING keyed on recipient+type+vehicle+validity date), so calling
--     it on every page load is cheap and never duplicates a notification.
--
-- Run after 0023_vehicle_document_fields.sql.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_role text not null check (recipient_role in ('operator', 'staff')),
  recipient_id uuid references public.profiles (id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  link text,
  related_table text,
  related_id uuid,
  related_date date,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint notifications_operator_has_recipient
    check (recipient_role = 'staff' or recipient_id is not null)
);

comment on column public.notifications.recipient_id is
  'Null only for a staff broadcast (recipient_role = staff) - a new '
  'request is everyone on staff''s to review, not targeted at one '
  'account. Always set for an operator notification.';

-- Dedup key for sync_expiry_notifications() only (partial index, scoped
-- to the two expiry types) - without `related_date`, a vehicle renewed
-- and then approaching expiry again later would never get a second
-- notification, since the first one (now read) would still match.
-- Deliberately NOT applied to the event-driven types below (booking/
-- vehicle/transfer pending/decided) - those can legitimately repeat for
-- the same row (e.g. an edited booking reverts to pending more than
-- once), so they have no such constraint and just insert every time
-- their trigger fires.
create unique index notifications_expiry_dedup_idx on public.notifications (
  type,
  related_id,
  recipient_role,
  coalesce(recipient_id, '00000000-0000-0000-0000-000000000000'::uuid),
  related_date
) where type in ('cpc_expiring', 'orcr_expiring');

create index notifications_recipient_idx on public.notifications (recipient_role, recipient_id, created_at desc);

alter table public.notifications enable row level security;

create policy notifications_select_own on public.notifications
  for select to authenticated
  using (
    (recipient_role = 'operator' and recipient_id = auth.uid())
    or (recipient_role = 'staff' and public.is_staff() and (recipient_id is null or recipient_id = auth.uid()))
  );

-- Only used to flip is_read - same predicate as select.
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (
    (recipient_role = 'operator' and recipient_id = auth.uid())
    or (recipient_role = 'staff' and public.is_staff() and (recipient_id is null or recipient_id = auth.uid()))
  );

-- No insert/delete policy for anyone - every row comes from a SECURITY
-- DEFINER function below, which bypasses RLS as the function owner.

/* --------------------------------------------------- booking triggers */

-- Fires on a brand-new request (insert) and on an edited booking that
-- reverts an already-decided booking back to pending
-- (request_booking_change) - both are "something new for staff to
-- review," not just the first one.
create or replace function public.notify_booking_pending()
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
      'booking_pending',
      'New booking request',
      new.operator_name || ' - ' || new.route || ' on ' || new.booking_date,
      'staff.html',
      'bookings',
      new.id
    )
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger bookings_notify_pending_insert
  after insert on public.bookings
  for each row execute function public.notify_booking_pending();

create trigger bookings_notify_pending_update
  after update on public.bookings
  for each row execute function public.notify_booking_pending();

create or replace function public.notify_booking_decided()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id)
    values (
      'operator',
      new.operator_id,
      'booking_' || new.status,
      case when new.status = 'approved' then 'Booking approved' else 'Booking declined' end,
      new.route || ' on ' || new.booking_date,
      'dashboard.html',
      'bookings',
      new.id
    )
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger bookings_notify_decided
  after update on public.bookings
  for each row execute function public.notify_booking_decided();

/* --------------------------------------------------- vehicle triggers */

create or replace function public.notify_vehicle_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending' then
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

create trigger vehicles_notify_pending
  after insert on public.vehicles
  for each row execute function public.notify_vehicle_pending();

create or replace function public.notify_vehicle_decided()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id)
    values (
      'operator',
      new.operator_id,
      'vehicle_' || new.status,
      case when new.status = 'approved' then 'Vehicle approved' else 'Vehicle declined' end,
      new.plate_no,
      'vehicles.html',
      'vehicles',
      new.id
    )
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger vehicles_notify_decided
  after update on public.vehicles
  for each row execute function public.notify_vehicle_decided();

/* ------------------------------------------------- transfer triggers */

-- Fires once the receiving operator confirms - only then is there
-- actually something for staff to review (transfer-approvals.html
-- already hides the approve/reject buttons until this happens).
create or replace function public.notify_transfer_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recipient_response = 'accepted' and old.recipient_response is distinct from 'accepted' then
    insert into public.notifications (recipient_role, type, title, body, link, related_table, related_id)
    values (
      'staff',
      'transfer_pending',
      'Transfer ready for approval',
      coalesce(new.from_operator_name, 'An operator') || ' - ' || coalesce(new.route, '') || ' on ' || new.booking_date,
      'transfer-approvals.html',
      'booking_transfers',
      new.id
    )
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger booking_transfers_notify_pending
  after update on public.booking_transfers
  for each row execute function public.notify_transfer_pending();

create or replace function public.notify_transfer_decided()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id)
    values (
      'operator',
      new.from_operator_id,
      'transfer_' || new.status,
      case when new.status = 'approved' then 'Transfer approved' else 'Transfer declined' end,
      coalesce(new.route, '') || ' on ' || new.booking_date,
      'dashboard.html',
      'booking_transfers',
      new.id
    )
    on conflict do nothing;

    if new.status = 'approved' then
      insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id)
      values (
        'operator',
        new.to_operator_id,
        'transfer_' || new.status,
        'Transfer approved - booking is now yours',
        coalesce(new.route, '') || ' on ' || new.booking_date,
        'my-schedule.html',
        'booking_transfers',
        new.id
      )
      on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;

create trigger booking_transfers_notify_decided
  after update on public.booking_transfers
  for each row execute function public.notify_transfer_decided();

/* --------------------------------------------------- expiry sync (rpc) */

create or replace function public.sync_expiry_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- CPC validity, operator side.
  insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id, related_date)
  select 'operator', v.operator_id, 'cpc_expiring',
    'CPC expiring soon',
    v.plate_no || ' - CPC valid until ' || v.cpc_validity,
    'vehicles.html', 'vehicles', v.id, v.cpc_validity
  from public.vehicles v
  where v.status = 'approved'
    and v.cpc_validity is not null
    and v.cpc_validity between current_date and current_date + 30
  on conflict do nothing;

  -- CPC validity, staff side (broadcast).
  insert into public.notifications (recipient_role, type, title, body, link, related_table, related_id, related_date)
  select 'staff', 'cpc_expiring',
    'CPC expiring soon',
    v.plate_no || ' - CPC valid until ' || v.cpc_validity,
    'vehicles-database.html', 'vehicles', v.id, v.cpc_validity
  from public.vehicles v
  where v.status = 'approved'
    and v.cpc_validity is not null
    and v.cpc_validity between current_date and current_date + 30
  on conflict do nothing;

  -- OR/CR validity, operator side.
  insert into public.notifications (recipient_role, recipient_id, type, title, body, link, related_table, related_id, related_date)
  select 'operator', v.operator_id, 'orcr_expiring',
    'OR/CR expiring soon',
    v.plate_no || ' - OR/CR valid until ' || v.orcr_validity,
    'vehicles.html', 'vehicles', v.id, v.orcr_validity
  from public.vehicles v
  where v.status = 'approved'
    and v.orcr_validity is not null
    and v.orcr_validity between current_date and current_date + 30
  on conflict do nothing;

  -- OR/CR validity, staff side (broadcast).
  insert into public.notifications (recipient_role, type, title, body, link, related_table, related_id, related_date)
  select 'staff', 'orcr_expiring',
    'OR/CR expiring soon',
    v.plate_no || ' - OR/CR valid until ' || v.orcr_validity,
    'vehicles-database.html', 'vehicles', v.id, v.orcr_validity
  from public.vehicles v
  where v.status = 'approved'
    and v.orcr_validity is not null
    and v.orcr_validity between current_date and current_date + 30
  on conflict do nothing;
end;
$$;

revoke all on function public.sync_expiry_notifications() from public, anon;
grant execute on function public.sync_expiry_notifications() to authenticated;

notify pgrst, 'reload schema';
