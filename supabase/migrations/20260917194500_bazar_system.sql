-- MessMate Bazar System
-- Permission-gated entry, pending approval, approval/rejection and audit trail.

alter table public.mess_settings
  add column if not exists bazar_approval_required boolean not null default true;

create or replace function public.create_bazar_entry(
  p_mess_id uuid,
  p_purchased_on date,
  p_total_amount numeric,
  p_note text default null,
  p_receipt_url text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_member_id uuid;
  v_entry_id uuid;
  v_status public.bazar_status;
begin
  select id into v_member_id
  from public.mess_members
  where mess_id=p_mess_id and user_id=auth.uid() and status='active';
  if v_member_id is null then raise exception 'Only active members can add bazar'; end if;
  if not public.has_mess_permission(p_mess_id,'can_add_bazar') then
    raise exception 'Bazar entry permission is required';
  end if;
  if p_total_amount < 0 then raise exception 'Amount cannot be negative'; end if;

  select case when bazar_approval_required then 'pending'::public.bazar_status else 'approved'::public.bazar_status end
  into v_status from public.mess_settings where mess_id=p_mess_id;

  insert into public.bazar_entries(mess_id,buyer_member_id,purchased_on,total_amount,status,note,receipt_url,approved_at,approved_by)
  values(p_mess_id,v_member_id,coalesce(p_purchased_on,current_date),p_total_amount,v_status,p_note,p_receipt_url,
    case when v_status='approved' then now() end,
    case when v_status='approved' then auth.uid() end)
  returning id into v_entry_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(p_mess_id,auth.uid(),'create','bazar_entry',v_entry_id,null,
    jsonb_build_object('status',v_status,'total_amount',p_total_amount,'purchased_on',p_purchased_on));
  return v_entry_id;
end; $$;

create or replace function public.review_bazar_entry(
  p_entry_id uuid,
  p_decision public.bazar_status,
  p_reason text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_entry public.bazar_entries%rowtype;
  v_mess_id uuid;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into v_entry from public.bazar_entries where id=p_entry_id;
  if not found then raise exception 'Bazar entry not found'; end if;
  v_mess_id := v_entry.mess_id;
  if not public.has_mess_permission(v_mess_id,'can_approve_bazar') then raise exception 'Bazar approval permission is required'; end if;
  if v_entry.status <> 'pending' then raise exception 'Only pending entries can be reviewed'; end if;

  update public.bazar_entries
  set status=p_decision, approved_at=case when p_decision='approved' then now() else null end,
      approved_by=case when p_decision='approved' then auth.uid() else null end, updated_at=now()
  where id=p_entry_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v_mess_id,auth.uid(),case when p_decision='approved' then 'approve' else 'reject' end,'bazar_entry',p_entry_id,
    jsonb_build_object('status',v_entry.status,'total_amount',v_entry.total_amount),
    jsonb_build_object('status',p_decision,'reason',p_reason));
end; $$;

create or replace function public.update_bazar_entry(
  p_entry_id uuid,
  p_purchased_on date,
  p_total_amount numeric,
  p_note text default null,
  p_receipt_url text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_entry public.bazar_entries%rowtype;
begin
  select * into v_entry from public.bazar_entries where id=p_entry_id;
  if not found then raise exception 'Bazar entry not found'; end if;
  if not public.has_mess_permission(v_entry.mess_id,'can_add_bazar') then raise exception 'Bazar entry permission is required'; end if;
  if not exists(select 1 from public.mess_members mm where mm.id=v_entry.buyer_member_id and mm.user_id=auth.uid())
     and not public.is_mess_manager(v_entry.mess_id) then raise exception 'You can only edit your own bazar entries'; end if;
  if v_entry.status='approved' then raise exception 'Approved bazar entries cannot be edited'; end if;
  if p_total_amount < 0 then raise exception 'Amount cannot be negative'; end if;

  update public.bazar_entries set purchased_on=p_purchased_on,total_amount=p_total_amount,note=p_note,receipt_url=p_receipt_url,updated_at=now() where id=p_entry_id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v_entry.mess_id,auth.uid(),'update','bazar_entry',p_entry_id,
    jsonb_build_object('status',v_entry.status,'total_amount',v_entry.total_amount,'purchased_on',v_entry.purchased_on),
    jsonb_build_object('status',v_entry.status,'total_amount',p_total_amount,'purchased_on',p_purchased_on));
end; $$;

create or replace function public.set_bazar_approval_required(p_mess_id uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager access required'; end if;
  update public.mess_settings set bazar_approval_required=p_enabled,updated_at=now() where mess_id=p_mess_id;
end; $$;

grant execute on function public.create_bazar_entry(uuid,date,numeric,text,text) to authenticated;
grant execute on function public.review_bazar_entry(uuid,public.bazar_status,text) to authenticated;
grant execute on function public.update_bazar_entry(uuid,date,numeric,text,text) to authenticated;
grant execute on function public.set_bazar_approval_required(uuid,boolean) to authenticated;
revoke all on function public.create_bazar_entry(uuid,date,numeric,text,text) from public;
revoke all on function public.review_bazar_entry(uuid,public.bazar_status,text) from public;
revoke all on function public.update_bazar_entry(uuid,date,numeric,text,text) from public;
revoke all on function public.set_bazar_approval_required(uuid,boolean) from public;
