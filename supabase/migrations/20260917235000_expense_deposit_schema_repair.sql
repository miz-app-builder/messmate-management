-- Repair: align Expense/Deposit RPCs with the original MessMate schema.
-- expenses: description, created_by
-- deposits: member_id, deposited_on, payment_method, recorded_by

create or replace function public.create_expense(
  p_mess_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_expense_date date,
  p_note text default null,
  p_receipt_url text default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_cat_mess uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_manager(p_mess_id) and not public.has_mess_permission(p_mess_id,'can_add_expense') then raise exception 'Expense permission is required'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Expense amount cannot be negative'; end if;
  if p_category_id is not null then
    select mess_id into v_cat_mess from public.expense_categories where id=p_category_id;
    if v_cat_mess is null or v_cat_mess<>p_mess_id then raise exception 'Expense category does not belong to this mess'; end if;
  end if;
  insert into public.expenses(mess_id,category_id,amount,expense_date,description,created_by)
  values(p_mess_id,p_category_id,p_amount,coalesce(p_expense_date,current_date),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,new_data)
  values(p_mess_id,auth.uid(),'create','expense',v_id,jsonb_build_object('amount',p_amount,'category_id',p_category_id,'expense_date',coalesce(p_expense_date,current_date),'description',p_note,'receipt_url',p_receipt_url,'status','approved'));
  return v_id;
end; $$;
grant execute on function public.create_expense(uuid,uuid,numeric,date,text,text) to authenticated;
revoke all on function public.create_expense(uuid,uuid,numeric,date,text,text) from public;

create or replace function public.update_expense(
  p_expense_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_expense_date date,
  p_note text default null,
  p_receipt_url text default null
)
returns boolean
language plpgsql security definer set search_path=public
as $$
declare v public.expenses%rowtype; v_cat_mess uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if v.status<>'approved' then raise exception 'Voided expense cannot be edited'; end if;
  if not public.is_mess_manager(v.mess_id) and not public.has_mess_permission(v.mess_id,'can_add_expense') then raise exception 'Expense permission is required'; end if;
  if p_amount is null or p_amount<0 then raise exception 'Expense amount cannot be negative'; end if;
  if p_category_id is not null then
    select mess_id into v_cat_mess from public.expense_categories where id=p_category_id;
    if v_cat_mess is null or v_cat_mess<>v.mess_id then raise exception 'Expense category does not belong to this mess'; end if;
  end if;
  update public.expenses set category_id=p_category_id,amount=p_amount,expense_date=coalesce(p_expense_date,v.expense_date),description=nullif(trim(p_note),''),updated_at=now() where id=p_expense_id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'update','expense',v.id,jsonb_build_object('amount',v.amount,'category_id',v.category_id,'expense_date',v.expense_date,'description',v.description),jsonb_build_object('amount',p_amount,'category_id',p_category_id,'expense_date',coalesce(p_expense_date,v.expense_date),'description',p_note,'receipt_url',p_receipt_url));
  return true;
end; $$;
grant execute on function public.update_expense(uuid,uuid,numeric,date,text,text) to authenticated;
revoke all on function public.update_expense(uuid,uuid,numeric,date,text,text) from public;

create or replace function public.void_expense(p_expense_id uuid,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
declare v public.expenses%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if v.status='voided' then return true; end if;
  update public.expenses set status='voided',updated_at=now() where id=v.id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'void','expense',v.id,jsonb_build_object('status','approved'),jsonb_build_object('status','voided','reason',p_reason));
  return true;
end; $$;
grant execute on function public.void_expense(uuid,text) to authenticated;
revoke all on function public.void_expense(uuid,text) from public;

create or replace function public.create_deposit(
  p_mess_id uuid,
  p_mess_member_id uuid,
  p_amount numeric,
  p_deposit_date date,
  p_method text default null,
  p_note text default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_member_mess uuid; v_status public.membership_status;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_manager(p_mess_id) and not public.has_mess_permission(p_mess_id,'can_record_deposit') then raise exception 'Deposit permission is required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Deposit amount must be greater than zero'; end if;
  select mess_id,status into v_member_mess,v_status from public.mess_members where id=p_mess_member_id;
  if v_member_mess is null or v_member_mess<>p_mess_id then raise exception 'Member does not belong to this mess'; end if;
  if v_status<>'active' then raise exception 'Deposits can only be recorded for active members'; end if;
  insert into public.deposits(mess_id,member_id,amount,deposited_on,payment_method,note,recorded_by)
  values(p_mess_id,p_mess_member_id,p_amount,coalesce(p_deposit_date,current_date),nullif(trim(p_method),''),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,new_data)
  values(p_mess_id,auth.uid(),'create','deposit',v_id,jsonb_build_object('member_id',p_mess_member_id,'amount',p_amount,'deposit_date',coalesce(p_deposit_date,current_date),'method',p_method,'status','approved'));
  return v_id;
end; $$;
grant execute on function public.create_deposit(uuid,uuid,numeric,date,text,text) to authenticated;
revoke all on function public.create_deposit(uuid,uuid,numeric,date,text,text) from public;

create or replace function public.void_deposit(p_deposit_id uuid,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
declare v public.deposits%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.deposits where id=p_deposit_id for update;
  if not found then raise exception 'Deposit not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if v.status='voided' then return true; end if;
  update public.deposits set status='voided' where id=v.id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'void','deposit',v.id,jsonb_build_object('status','approved'),jsonb_build_object('status','voided','reason',p_reason));
  return true;
end; $$;
grant execute on function public.void_deposit(uuid,text) to authenticated;
revoke all on function public.void_deposit(uuid,text) from public;
