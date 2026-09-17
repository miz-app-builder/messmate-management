-- MessMate accounting integrity hardening
-- 1) Deposits become ledger credits automatically and voiding removes their system ledger row.
-- 2) Closed monthly settlements are immutable; corrections use audited ledger adjustments.
-- 3) Monthly settlements cannot be modified directly by the client.

-- Closed settlements must not be recalculated/overwritten.
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
  v_settlement public.monthly_settlements%rowtype;
  v_rate numeric(14,4) := 0;
  v_meals numeric(14,2) := 0;
  v_other numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  if p_month_start <> date_trunc('month',p_month_start)::date then raise exception 'Month start must be the first day of the month'; end if;

  select * into v_member from public.mess_members where id=p_member_id and mess_id=p_mess_id;
  if not found then raise exception 'Member not found in this mess'; end if;
  if v_member.status not in ('active','left') then raise exception 'Only active or left members can be settled'; end if;

  -- A closed snapshot is final. Do not silently recalculate it.
  select * into v_settlement
  from public.monthly_settlements
  where mess_id=p_mess_id and member_id=p_member_id and month_start=p_month_start
  for update;
  if found and v_settlement.status='closed' then
    raise exception 'Monthly settlement is already closed and immutable';
  end if;

  perform public.calculate_meal_rate(p_mess_id,p_month_start,v_end);
  select coalesce(rate,0) into v_rate from public.meal_rates
  where mess_id=p_mess_id and period_start=p_month_start;

  select count(*)::numeric into v_meals
  from public.meal_entries me
  where me.member_id=p_member_id and me.meal_date between p_month_start and v_end and me.status='on'
    and me.meal_date >= coalesce((v_member.activated_at at time zone 'Asia/Dhaka')::date,p_month_start)
    and (v_member.left_at is null or me.meal_date <= (v_member.left_at at time zone 'Asia/Dhaka')::date);

  select coalesce(sum(debit),0) into v_other from public.ledger_entries
  where member_id=p_member_id and entry_date between p_month_start and v_end and entry_type in ('other_cost','adjustment');
  select coalesce(sum(credit),0) into v_paid from public.ledger_entries
  where member_id=p_member_id and entry_date between p_month_start and v_end and entry_type in ('deposit','refund');

  v_total := round((v_meals*v_rate)+v_other-v_paid,2);

  insert into public.monthly_settlements(
    mess_id,member_id,month_start,month_end,total_meals,meal_cost,other_cost,total_paid,balance,status,closed_at,closed_by
  )
  values(
    p_mess_id,p_member_id,p_month_start,v_end,v_meals,v_meals*v_rate,v_other,v_paid,v_total,'closed',now(),auth.uid()
  )
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

-- Re-running month close is idempotent: already-closed members are skipped.
create or replace function public.close_month_for_mess(p_mess_id uuid,p_month_start date)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare r record; n integer:=0;
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  for r in
    select mm.id
    from public.mess_members mm
    where mm.mess_id=p_mess_id and mm.status in ('active','left')
      and not exists (
        select 1 from public.monthly_settlements ms
        where ms.mess_id=mm.mess_id and ms.member_id=mm.id and ms.month_start=p_month_start and ms.status='closed'
      )
  loop
    perform public.create_monthly_settlement(p_mess_id,r.id,p_month_start);
    n:=n+1;
  end loop;
  return n;
end;
$$;

grant execute on function public.close_month_for_mess(uuid,date) to authenticated;
revoke all on function public.close_month_for_mess(uuid,date) from public;

-- Client-side direct settlement writes are not allowed; RPCs remain the write path.
drop policy if exists settlements_manage_manager on public.monthly_settlements;

-- Deposit -> ledger synchronization.
create or replace function public.sync_deposit_to_ledger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    insert into public.ledger_entries(
      mess_id,member_id,entry_date,entry_type,debit,credit,reference_id,description,source
    )
    values(
      new.mess_id,new.member_id,new.deposited_on,'deposit',0,new.amount,new.id,
      coalesce(nullif(trim(new.note),''),'Member deposit'),'system'
    );
    return new;
  elsif tg_op='UPDATE' then
    if new.status='voided' and old.status<>'voided' then
      delete from public.ledger_entries
      where reference_id=new.id and entry_type='deposit' and source='system';
    elsif new.status<>'voided' and old.status='voided' then
      insert into public.ledger_entries(
        mess_id,member_id,entry_date,entry_type,debit,credit,reference_id,description,source
      )
      values(
        new.mess_id,new.member_id,new.deposited_on,'deposit',0,new.amount,new.id,
        coalesce(nullif(trim(new.note),''),'Member deposit'),'system'
      );
    end if;
    return new;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_deposit_ledger_sync on public.deposits;
create trigger trg_deposit_ledger_sync
after insert or update of status on public.deposits
for each row execute function public.sync_deposit_to_ledger();

revoke all on function public.sync_deposit_to_ledger() from public, authenticated;
grant execute on function public.sync_deposit_to_ledger() to service_role;
