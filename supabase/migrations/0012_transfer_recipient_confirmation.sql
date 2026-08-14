-- Requires the receiving operator to confirm a transfer request before
-- PITX staff can approve it - the "internal agreement" between the two
-- operators was previously taken on the sending operator's word alone;
-- now the receiving side has to actually say yes in-app first.
--
-- Run after 0011_operator_directory.sql.

alter table public.booking_transfers
  add column if not exists recipient_response text not null default 'pending'
    check (recipient_response in ('pending', 'accepted', 'declined')),
  add column if not exists recipient_responded_at timestamptz;

comment on column public.booking_transfers.recipient_response is
  'Whether the receiving operator has confirmed the handoff. Staff can
   only approve_booking_transfer() once this is ''accepted''.';

-- ---------------------------------------------------------------------------
-- accept_booking_transfer / decline_booking_transfer: the receiving
-- operator's response, checked against to_operator_id = auth.uid() so
-- only the actual recipient can respond.
-- ---------------------------------------------------------------------------
create or replace function public.accept_booking_transfer(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.booking_transfers%rowtype;
begin
  select * into v_transfer
  from public.booking_transfers
  where id = p_transfer_id and to_operator_id = auth.uid() and status = 'pending'
  for update;

  if v_transfer.id is null then
    raise exception 'Transfer request not found or already decided.';
  end if;
  if v_transfer.recipient_response <> 'pending' then
    raise exception 'You already responded to this transfer request.';
  end if;

  update public.booking_transfers set
    recipient_response = 'accepted',
    recipient_responded_at = now()
  where id = p_transfer_id;
end;
$$;

revoke all on function public.accept_booking_transfer(uuid) from public, anon;
grant execute on function public.accept_booking_transfer(uuid) to authenticated;

create or replace function public.decline_booking_transfer(p_transfer_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.booking_transfers%rowtype;
begin
  select * into v_transfer
  from public.booking_transfers
  where id = p_transfer_id and to_operator_id = auth.uid() and status = 'pending'
  for update;

  if v_transfer.id is null then
    raise exception 'Transfer request not found or already decided.';
  end if;
  if v_transfer.recipient_response <> 'pending' then
    raise exception 'You already responded to this transfer request.';
  end if;

  -- Declining closes the request outright - it never reaches staff, since
  -- there's nothing for them to approve without the recipient's consent.
  update public.booking_transfers set
    recipient_response = 'declined',
    recipient_responded_at = now(),
    status = 'rejected',
    rejection_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_transfer_id;
end;
$$;

revoke all on function public.decline_booking_transfer(uuid, text) from public, anon;
grant execute on function public.decline_booking_transfer(uuid, text) to authenticated;

-- approve_booking_transfer now also requires the recipient to have
-- accepted first - staff approval alone is no longer enough.
create or replace function public.approve_booking_transfer(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer public.booking_transfers%rowtype;
  v_booking public.bookings%rowtype;
  v_to_name text;
begin
  if not public.is_staff() then
    raise exception 'Only PITX staff can decide on transfers.';
  end if;

  select * into v_transfer
  from public.booking_transfers
  where id = p_transfer_id and status = 'pending'
  for update;

  if v_transfer.id is null then
    raise exception 'Transfer request not found or already decided.';
  end if;
  if v_transfer.recipient_response <> 'accepted' then
    raise exception 'The receiving operator has not confirmed this transfer yet.';
  end if;

  select * into v_booking from public.bookings where id = v_transfer.booking_id for update;
  if v_booking.id is null then
    raise exception 'The original booking no longer exists.';
  end if;

  select coalesce(operator_name, username) into v_to_name
  from public.profiles where id = v_transfer.to_operator_id;

  update public.bookings set
    previous_operator_name = v_booking.operator_name,
    operator_id = v_transfer.to_operator_id,
    operator_name = coalesce(v_to_name, v_booking.operator_name),
    plate_no = v_transfer.new_plate_no
  where id = v_booking.id;

  update public.booking_transfers set
    status = 'approved',
    decided_by = auth.uid(),
    decided_at = now()
  where id = p_transfer_id;
end;
$$;

notify pgrst, 'reload schema';
