-- Final admin/accounting hardening for MessMate.
-- Make approval/permission/cutoff settings writable only through controlled RPCs.
-- Also correct refund credits in member balance calculation.

-- 1) Prevent direct manager updates that can bypass approval/audit workflows.
drop policy if exists join_requests_update_manager on public.join_requests;
drop policy if exists members_update_manager on public.mess_members;
drop policy if exists member_permissions_update_manager on public.member_permissions;
drop policy if exists cutoff_manage_manager on public.meal_cutoff_settings;
drop policy if exists settings_update_manager on public.mess_settings;

-- 2) Controlled member-permission management with target validation and audit.
create or replace function public.set_member_permissions(
  p_mess_member_id uuid,
  p_can_add_bazar boolean default false,
  p_can_approve_bazar boolean default false,
  p_can_add_expense boolean default false,
  p_can_record_deposit boolean default false,
  p_can_manage_meals boolean default false,
  p_can_view_reports boolean default false
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v public.mess_members%rowtype;
  v_old jsonb;
  v_new jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into v from public.mess_members where id=p_mess_member_id;
  if not found then raise exception 'Member not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if v.status not in ('active','pending') then raise exception 'Member is not eligible for permission management'; end if;

  select jsonb_build_object(
    'can_add_bazar',coalesce(can_add_bazar,false),
    'can_approve_bazar',coalesce(can_approve_bazar,false),
    'can_add_expense',coalesce(can_add_expense,false),
    'can_record_deposit',coalesce(can_record_deposit,false),
    'can_manage_meals',coalesce(can_manage_meals,false),
    'can_view_reports',coalesce(can_view_reports,false)
  ) into v_old
  from public.member_permissions where mess_member_id=p_mess_member_id;

  insert into public.member_permissions(
    mess_member_id,can_add_bazar,can_approve_bazar,can_add_expense,
    can_record_deposit,can_manage_meals,can_view_reports,updated_at
  ) values(
    p_mess_member_id,p_can_add_bazar,p_can_approve_bazar,p_can_add_expense,
    p_can_record_deposit,p_can_manage_meals,p_can_view_reports,now()
  )
  on conflict(mess_member_id) do update set
    can_add_bazar=excluded.can_add_bazar,
    can_approve_bazar=excluded.can_approve_bazar,
    can_add_expense=excluded.can_add_expense,
    can_record_deposit=excluded.can_record_deposit,
    can_manage_meals=excluded.can_manage_meals,
    can_view_reports=excluded.can_view_reports,
    updated_at=now();

  select jsonb_build_object(
    'can_add_bazar',can_add_bazar,
    'can_approve_bazar',can_approve_bazar,
    'can_add_expense',can_add_expense,
    'can_record_deposit',can_record_deposit,
    'can_manage_meals',can_manage_meals,
    'can_view_reports',can_view_reports
  ) into v_new
  from public.member_permissions where mess_member_id=p_mess_member_id;

  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values(v.mess_id,auth.uid(),'update','member_permissions',p_mess_member_id,v_old,v_new);
end;
$$;

grant execute on function public.set_member_permissions(uuid,boolean,boolean,boolean,boolean,boolean,boolean) to authenticated;
revoke all on function public.set_member_permissions(uuid,boolean,boolean,boolean,boolean,boolean,boolean) from public;

-- 3) Fix balance math: refunds are credits, not debits.
create or replace function public.get_member_balance(
  p_mess_member_id uuid,
  p_period_start date default null,
  p_period_end date default null
)
returns table(
  member_id uuid,
  total_meals numeric,
  meal_cost numeric,
  other_cost numeric,
  total_debit numeric,
  total_paid numeric,
  balance numeric,
  balance_status text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_mess_id uuid;
  v_start date := coalesce(p_period_start, date_trunc('month',current_date)::date);
  v_end date := coalesce(p_period_end, (date_trunc('month',current_date)+interval '1 month - 1 day')::date);
  v_meals numeric := 0;
  v_meal_cost numeric := 0;
  v_other numeric := 0;
  v_paid numeric := 0;
  v_refund numeric := 0;
  v_rate numeric := 0;
  v_activation date;
  v_left date;
begin
  select mess_id,(activated_at at time zone 'Asia/Dhaka')::date,(left_at at time zone 'Asia/Dhaka')::date
  into v_mess_id,v_activation,v_left
  from public.mess_members where id=p_mess_member_id;
  if v_mess_id is null then raise exception 'Member not found'; end if;
  if not public.is_mess_member(v_mess_id)
     and not exists(select 1 from public.mess_members x where x.id=p_mess_member_id and x.user_id=auth.uid()) then
    raise exception 'Not authorized';
  end if;

  select coalesce(rate,0) into v_rate
  from public.meal_rates
  where mess_id=v_mess_id and period_start=v_start limit 1;
  if v_rate is null then v_rate:=0; end if;

  select count(*)::numeric into v_meals
  from public.meal_entries me
  where me.member_id=p_mess_member_id
    and me.meal_date between v_start and v_end
    and me.status='on'
    and me.meal_date >= coalesce(v_activation,v_start)
    and (v_left is null or me.meal_date <= v_left);
  v_meal_cost:=round(v_meals*v_rate,2);

  select coalesce(sum(debit),0)
  into v_other
  from public.ledger_entries le
  where le.member_id=p_mess_member_id
    and le.entry_date between v_start and v_end
    and le.entry_type in ('other_cost','adjustment');

  select coalesce(sum(credit),0)
  into v_paid
  from public.ledger_entries le
  where le.member_id=p_mess_member_id
    and le.entry_date between v_start and v_end
    and le.entry_type in ('deposit','refund');

  v_refund:=coalesce((select sum(credit) from public.ledger_entries le
    where le.member_id=p_mess_member_id and le.entry_date between v_start and v_end and le.entry_type='refund'),0);

  return query select
    p_mess_member_id,
    v_meals,
    v_meal_cost,
    v_other,
    round(v_meal_cost+v_other,2),
    round(v_paid,2),
    round((v_meal_cost+v_other)-v_paid,2),
    case when round((v_meal_cost+v_other)-v_paid,2)>0 then 'due'
         when round((v_meal_cost+v_other)-v_paid,2)<0 then 'advance'
         else 'settled' end;
end;
$$;

grant execute on function public.get_member_balance(uuid,date,date) to authenticated;
revoke all on function public.get_member_balance(uuid,date,date) from public;

-- Note: approval/status changes remain available through the existing
-- request-review workflow RPC, which performs activation and audit together.
-- Meal cutoff changes remain available through save_meal_cutoff().
-- Mess-wide setting writes are intentionally disabled until an audited
-- settings RPC is introduced; current frontend uses dedicated setting RPCs.
