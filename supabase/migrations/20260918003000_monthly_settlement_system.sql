-- MessMate monthly settlement engine
-- Finalizes a member's monthly accounting snapshot. Closed settlements are immutable;
-- corrections must be made through the audited ledger adjustment flow.

create or replace function public.create_monthly_settlement(
  p_mess_id uuid,
  p_member_id uuid,
  p_month_start date
)
returns public.monthly_settlements
language plpgsql
security definer
set search_path=public
as $$
declare
  v_member public.mess_members%rowtype;
  v_end date := (date_trunc('month',p_month_start)+interval '1 month - 1 day')::date;
  v_balance record;
  v_rate numeric(14,4) := 0;
  v_other numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_settlement public.monthly_settlements%rowtype;
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  if p_month_start <> date_trunc('month',p_month_start)::date then raise exception 'Month start must be the first day of the month'; end if;

  select * into v_member from public.mess_members where id=p_member_id and mess_id=p_mess_id;
  if not found then raise exception 'Member not found in this mess'; end if;
  if v_member.status not in ('active','left') then raise exception 'Only active or left members can be settled'; end if;

  perform public.calculate_meal_rate(p_mess_id,p_month_start,v_end);
  select coalesce(rate,0) into v_rate from public.meal_rates where mess_id=p_mess_id and period_start=p_month_start;

  select count(*)::numeric into v_balance
  from public.meal_entries me
  where me.member_id=p_member_id and me.meal_date between p_month_start and v_end and me.status='on'
    and me.meal_date >= coalesce((v_member.activated_at at time zone 'Asia/Dhaka')::date,p_month_start)
    and (v_member.left_at is null or me.meal_date <= (v_member.left_at at time zone 'Asia/Dhaka')::date);

  select coalesce(sum(debit),0) into v_other from public.ledger_entries
  where member_id=p_member_id and entry_date between p_month_start and v_end and entry_type in ('other_cost','adjustment');
  select coalesce(sum(credit),0) into v_paid from public.ledger_entries
  where member_id=p_member_id and entry_date between p_month_start and v_end and entry_type in ('deposit','refund');

  v_total := round((v_balance::numeric*v_rate)+v_other-v_paid,2);

  insert into public.monthly_settlements(mess_id,member_id,month_start,month_end,total_meals,meal_cost,other_cost,total_paid,balance,status,closed_at,closed_by)
  values(p_mess_id,p_member_id,p_month_start,v_end,v_balance,v_balance*v_rate,v_other,v_paid,v_total,'closed',now(),auth.uid())
  on conflict(mess_id,member_id,month_start) do update set
    month_end=excluded.month_end,total_meals=excluded.total_meals,meal_cost=excluded.meal_cost,
    other_cost=excluded.other_cost,total_paid=excluded.total_paid,balance=excluded.balance,
    status='closed',closed_at=now(),closed_by=auth.uid();

  select * into v_settlement from public.monthly_settlements
  where mess_id=p_mess_id and member_id=p_member_id and month_start=p_month_start;

  insert into public.audit_logs(mess_id,actor_user_id,entity_type,entity_id,action,new_data)
  values(p_mess_id,auth.uid(),'monthly_settlement',v_settlement.id,'close',to_jsonb(v_settlement));
  return v_settlement;
end;
$$;

grant execute on function public.create_monthly_settlement(uuid,uuid,date) to authenticated;
revoke all on function public.create_monthly_settlement(uuid,uuid,date) from public;

create or replace function public.close_month_for_mess(p_mess_id uuid,p_month_start date)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare r record; n integer:=0;
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  for r in select id from public.mess_members where mess_id=p_mess_id and status in ('active','left') loop
    perform public.create_monthly_settlement(p_mess_id,r.id,p_month_start);
    n:=n+1;
  end loop;
  return n;
end;
$$;

grant execute on function public.close_month_for_mess(uuid,date) to authenticated;
revoke all on function public.close_month_for_mess(uuid,date) from public;

create or replace function public.get_monthly_settlement(
  p_mess_member_id uuid,
  p_month_start date
)
returns public.monthly_settlements
language plpgsql
security definer
set search_path=public
as $$
declare v public.monthly_settlements%rowtype;
begin
  select * into v from public.monthly_settlements where member_id=p_mess_member_id and month_start=p_month_start limit 1;
  if not found then raise exception 'Settlement not found'; end if;
  if not public.is_mess_member(v.mess_id) and not exists(select 1 from public.mess_members where id=p_mess_member_id and user_id=auth.uid()) then raise exception 'Not authorized'; end if;
  return v;
end;
$$;

grant execute on function public.get_monthly_settlement(uuid,date) to authenticated;
revoke all on function public.get_monthly_settlement(uuid,date) from public;
