-- MessMate Expense + Deposit System
-- Financial records only apply to active mess members.

alter table public.expenses
  add column if not exists status text not null default 'approved';

alter table public.expenses
  add column if not exists created_by uuid references auth.users(id);

alter table public.deposits
  add column if not exists status text not null default 'approved';

alter table public.deposits
  add column if not exists created_by uuid references auth.users(id);

alter table public.expenses
  drop constraint if exists expenses_status_check;
alter table public.expenses
  add constraint expenses_status_check check (status in ('approved','voided'));

alter table public.deposits
  drop constraint if exists deposits_status_check;
alter table public.deposits
  add constraint deposits_status_check check (status in ('approved','voided'));

create index if not exists expenses_mess_date_idx
  on public.expenses(mess_id, expense_date desc);
create index if not exists deposits_mess_date_idx
  on public.deposits(mess_id, deposit_date desc);
create index if not exists deposits_member_date_idx
  on public.deposits(mess_member_id, deposit_date desc);

-- Manager/authorized users can record an expense. Manager has implicit access.
create or replace function public.create_expense(
  p_mess_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_expense_date date,
  p_note text default null,
  p_receipt_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry_id uuid;
  v_category_mess_id uuid;
  v_old jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_manager(p_mess_id)
     and not public.has_mess_permission(p_mess_id, 'can_add_expense') then
    raise exception 'Expense permission is required';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'Expense amount cannot be negative'; end if;
  if p_category_id is not null then
    select mess_id into v_category_mess_id from public.expense_categories where id=p_category_id;
    if v_category_mess_id is null or v_category_mess_id <> p_mess_id then
      raise exception 'Expense category does not belong to this mess';
    end if;
  end if;

  insert into public.expenses(
    mess_id, category_id, amount, expense_date, note, receipt_url, status, created_by
  )
  values(
    p_mess_id, p_category_id, p_amount, coalesce(p_expense_date,current_date),
    nullif(trim(p_note),''), nullif(trim(p_receipt_url),''), 'approved', auth.uid()
  )
  returning id into v_entry_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(p_mess_id,auth.uid(),'create','expense',v_entry_id,null,
         jsonb_build_object('amount',p_amount,'category_id',p_category_id,'expense_date',coalesce(p_expense_date,current_date),'status','approved'));
  return v_entry_id;
end;
$$;

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
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.expenses%rowtype;
  v_category_mess_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if v.status <> 'approved' then raise exception 'Voided expense cannot be edited'; end if;
  if not public.is_mess_manager(v.mess_id)
     and not public.has_mess_permission(v.mess_id, 'can_add_expense') then
    raise exception 'Expense permission is required';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'Expense amount cannot be negative'; end if;
  if p_category_id is not null then
    select mess_id into v_category_mess_id from public.expense_categories where id=p_category_id;
    if v_category_mess_id is null or v_category_mess_id <> v.mess_id then raise exception 'Expense category does not belong to this mess'; end if;
  end if;

  update public.expenses
  set category_id=p_category_id, amount=p_amount, expense_date=coalesce(p_expense_date,v.expense_date),
      note=nullif(trim(p_note),''), receipt_url=nullif(trim(p_receipt_url),''), updated_at=now()
  where id=p_expense_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'update','expense',v.id,
         jsonb_build_object('amount',v.amount,'category_id',v.category_id,'expense_date',v.expense_date,'note',v.note),
         jsonb_build_object('amount',p_amount,'category_id',p_category_id,'expense_date',coalesce(p_expense_date,v.expense_date),'note',p_note));
  return true;
end;
$$;

grant execute on function public.update_expense(uuid,uuid,numeric,date,text,text) to authenticated;
revoke all on function public.update_expense(uuid,uuid,numeric,date,text,text) from public;

create or replace function public.void_expense(p_expense_id uuid, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v public.expenses%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if v.status='voided' then return true; end if;
  update public.expenses set status='voided', updated_at=now() where id=v.id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'void','expense',v.id,jsonb_build_object('status','approved'),jsonb_build_object('status','voided','reason',p_reason));
  return true;
end;
$$;

grant execute on function public.void_expense(uuid,text) to authenticated;
revoke all on function public.void_expense(uuid,text) from public;

-- Deposit/payment recorded for an active member only.
create or replace function public.create_deposit(
  p_mess_id uuid,
  p_mess_member_id uuid,
  p_amount numeric,
  p_deposit_date date,
  p_method text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit_id uuid;
  v_member_mess_id uuid;
  v_member_status public.membership_status;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_manager(p_mess_id)
     and not public.has_mess_permission(p_mess_id, 'can_record_deposit') then
    raise exception 'Deposit permission is required';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Deposit amount must be greater than zero'; end if;

  select mess_id,status into v_member_mess_id,v_member_status
  from public.mess_members where id=p_mess_member_id;
  if v_member_mess_id is null or v_member_mess_id <> p_mess_id then raise exception 'Member does not belong to this mess'; end if;
  if v_member_status <> 'active' then raise exception 'Deposits can only be recorded for active members'; end if;

  insert into public.deposits(
    mess_id, mess_member_id, amount, deposit_date, method, note, status, created_by
  )
  values(
    p_mess_id,p_mess_member_id,p_amount,coalesce(p_deposit_date,current_date),nullif(trim(p_method),''),nullif(trim(p_note),''),'approved',auth.uid()
  )
  returning id into v_deposit_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(p_mess_id,auth.uid(),'create','deposit',v_deposit_id,null,
         jsonb_build_object('member_id',p_mess_member_id,'amount',p_amount,'deposit_date',coalesce(p_deposit_date,current_date),'method',p_method,'status','approved'));
  return v_deposit_id;
end;
$$;

grant execute on function public.create_deposit(uuid,uuid,numeric,date,text,text) to authenticated;
revoke all on function public.create_deposit(uuid,uuid,numeric,date,text,text) from public;

create or replace function public.void_deposit(p_deposit_id uuid, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v public.deposits%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.deposits where id=p_deposit_id for update;
  if not found then raise exception 'Deposit not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if v.status='voided' then return true; end if;
  update public.deposits set status='voided', updated_at=now() where id=v.id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'void','deposit',v.id,jsonb_build_object('status','approved'),jsonb_build_object('status','voided','reason',p_reason));
  return true;
end;
$$;

grant execute on function public.void_deposit(uuid,text) to authenticated;
revoke all on function public.void_deposit(uuid,text) from public;

-- Safe category seed set. Existing custom categories are preserved.
insert into public.expense_categories(mess_id,name)
select m.id, c.name
from public.messes m
cross join (values ('Rent'),('Gas'),('Electricity'),('Internet'),('Water'),('Maid'),('Cleaning'),('Other')) c(name)
where not exists (
  select 1 from public.expense_categories ec
  where ec.mess_id=m.id and lower(ec.name)=lower(c.name)
);
