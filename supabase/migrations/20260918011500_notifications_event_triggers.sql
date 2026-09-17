-- Notification event wiring. Uses existing notifications.body schema.
create or replace function public.create_notification(
  p_mess_id uuid,
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text default 'info'
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  insert into public.notifications(user_id,mess_id,title,body,type)
  values(p_user_id,p_mess_id,trim(p_title),trim(p_message),coalesce(p_type,'info'))
  returning id into v_id;
  return v_id;
end; $$;
grant execute on function public.create_notification(uuid,uuid,text,text,text) to authenticated;
revoke all on function public.create_notification(uuid,uuid,text,text,text) from public;

create or replace function public.notify_join_request_event()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  if tg_op='INSERT' and new.status='pending' then
    select coalesce(full_name,'A member') into v_name from public.profiles where id=new.user_id;
    insert into public.notifications(user_id,mess_id,title,body,type)
    select mm.user_id,new.mess_id,'New join request',v_name || ' requested to join your mess.','join_request'
    from public.mess_members mm where mm.mess_id=new.mess_id and mm.role='manager' and mm.status='active';
  elsif tg_op='UPDATE' and old.status is distinct from new.status and new.status in ('approved','rejected') then
    insert into public.notifications(user_id,mess_id,title,body,type)
    values(new.user_id,new.mess_id,case when new.status='approved' then 'Join request approved' else 'Join request rejected' end,
      case when new.status='approved' then 'Your request to join the mess was approved.' else 'Your request to join the mess was rejected.' end,
      case when new.status='approved' then 'success' else 'warning' end);
  end if;
  return new;
end; $$;
drop trigger if exists trg_notify_join_request on public.join_requests;
create trigger trg_notify_join_request after insert or update of status on public.join_requests for each row execute function public.notify_join_request_event();

create or replace function public.notify_bazar_event()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  if tg_op='INSERT' and new.status='pending' then
    select coalesce(p.full_name,'A member') into v_name from public.mess_members mm left join public.profiles p on p.id=mm.user_id where mm.id=new.buyer_member_id;
    insert into public.notifications(user_id,mess_id,title,body,type)
    select mm.user_id,new.mess_id,'Bazar approval needed',v_name || ' submitted a bazar entry for approval.','bazar'
    from public.mess_members mm where mm.mess_id=new.mess_id and mm.status='active' and (mm.role in ('manager','bazar_manager') or exists(select 1 from public.member_permissions mp where mp.mess_member_id=mm.id and mp.can_approve_bazar));
  elsif tg_op='UPDATE' and old.status is distinct from new.status and new.status in ('approved','rejected') then
    insert into public.notifications(user_id,mess_id,title,body,type)
    select mm.user_id,new.mess_id,case when new.status='approved' then 'Bazar approved' else 'Bazar rejected' end,
      case when new.status='approved' then 'Your bazar entry has been approved.' else 'Your bazar entry has been rejected.' end,
      case when new.status='approved' then 'success' else 'warning' end
    from public.mess_members mm where mm.id=new.buyer_member_id;
  end if;
  return new;
end; $$;
drop trigger if exists trg_notify_bazar on public.bazar_entries;
create trigger trg_notify_bazar after insert or update of status on public.bazar_entries for each row execute function public.notify_bazar_event();

create or replace function public.notify_deposit_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.notifications(user_id,mess_id,title,body,type)
    select mm.user_id,new.mess_id,'Deposit recorded','A deposit of ' || to_char(new.amount,'FM999999990.00') || ' has been recorded for your account.','success'
    from public.mess_members mm where mm.id=new.member_id;
  end if;
  return new;
end; $$;
drop trigger if exists trg_notify_deposit on public.deposits;
create trigger trg_notify_deposit after insert on public.deposits for each row execute function public.notify_deposit_event();

create or replace function public.notify_due_settlement_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' or (tg_op='UPDATE' and old.balance is distinct from new.balance) then
    if new.balance > 0 then
      insert into public.notifications(user_id,mess_id,title,body,type)
      select mm.user_id,new.mess_id,'Balance due','Your current settlement shows a due balance of ' || to_char(new.balance,'FM999999990.00') || '.','warning'
      from public.mess_members mm where mm.id=new.member_id;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_notify_settlement_due on public.monthly_settlements;
create trigger trg_notify_settlement_due after insert or update of balance on public.monthly_settlements for each row execute function public.notify_due_settlement_event();
