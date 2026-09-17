-- MessMate accounting engine: meal rate, ledger and live member balance.
-- Food cost is based on approved Bazar purchases. Other expenses remain separate
-- until an explicit allocation rule is introduced.

alter table public.ledger_entries
  add column if not exists source text not null default 'manual';

create index if not exists ledger_member_entry_type_date_idx
  on public.ledger_entries(member_id, entry_type, entry_date);

create or replace function public.calculate_meal_rate(
  p_mess_id uuid,
  p_period_start date,
  p_period_end date
)
returns public.meal_rates
language plpgsql
security definer
set search_path=public
as $$
declare
  v_rate public.meal_rates%rowtype;
  v_food numeric(14,2) := 0;
  v_meals numeric(14,2) := 0;
  v_rate_value numeric(14,4) := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_member(p_mess_id) then raise exception 'Active mess membership is required'; end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'Invalid accounting period';
  end if;

  select coalesce(sum(total_amount),0)::numeric(14,2)
  into v_food
  from public.bazar_entries
  where mess_id=p_mess_id
    and status='approved'
    and purchased_on between p_period_start and p_period_end;

  select coalesce(count(*)::numeric,0)
  into v_meals
  from public.meal_entries me
  join public.mess_members mm on mm.id=me.member_id
  where me.mess_id=p_mess_id
    and me.meal_date between p_period_start and p_period_end
    and me.status='on'
    and me.meal_date >= (mm.activated_at at time zone 'Asia/Dhaka')::date
    and (mm.left_at is null or me.meal_date <= (mm.left_at at time zone 'Asia/Dhaka')::date);

  if v_meals > 0 then v_rate_value := round(v_food / v_meals,4); end if;

  insert into public.meal_rates(mess_id,period_start,period_end,food_cost,total_meals,rate)
  values(p_mess_id,p_period_start,p_period_end,v_food,v_meals,v_rate_value)
  on conflict(mess_id,period_start) do update set
    period_end=excluded.period_end,
    food_cost=excluded.food_cost,
    total_meals=excluded.total_meals,
    rate=excluded.rate;

  select * into v_rate from public.meal_rates where mess_id=p_mess_id and period_start=p_period_start;
  return v_rate;
end;
$$;

grant execute on function public.calculate_meal_rate(uuid,date,date) to authenticated;
revoke all on function public.calculate_meal_rate(uuid,date,date) from public;

create or replace function public.get_member_balance(p_mess_member_id uuid, p_period_start date default null, p_period_end date default null)
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
  v_rate numeric := 0;
  v_activation date;
  v_left date;
begin
  select mess_id,(activated_at at time zone 'Asia/Dhaka')::date,(left_at at time zone 'Asia/Dhaka')::date
  into v_mess_id,v_activation,v_left
  from public.mess_members where id=p_mess_member_id;
  if v_mess_id is null then raise exception 'Member not found'; end if;
  if not public.is_mess_member(v_mess_id) and not exists(select 1 from public.mess_members x where x.id=p_mess_member_id and x.user_id=auth.uid()) then
    raise exception 'Not authorized';
  end if;

  select coalesce(rate,0) into v_rate from public.meal_rates
  where mess_id=v_mess_id and period_start=v_start limit 1;
  if v_rate is null then v_rate:=0; end if;

  select count(*)::numeric into v_meals
  from public.meal_entries me
  where me.member_id=p_mess_member_id and me.meal_date between v_start and v_end and me.status='on'
    and me.meal_date >= coalesce(v_activation,v_start)
    and (v_left is null or me.meal_date <= v_left);
  v_meal_cost:=round(v_meals*v_rate,2);

  select coalesce(sum(debit),0),coalesce(sum(credit),0)
  into v_other,v_paid
  from public.ledger_entries le
  where le.member_id=p_mess_member_id and le.entry_date between v_start and v_end
    and le.entry_type in ('other_cost','adjustment','refund');

  select coalesce(sum(credit),0) into v_paid
  from public.ledger_entries le
  where le.member_id=p_mess_member_id and le.entry_date between v_start and v_end and le.entry_type='deposit';

  return query select p_mess_member_id,v_meals,v_meal_cost,v_other,
    round(v_meal_cost+v_other,2),round(v_paid,2),round((v_meal_cost+v_other)-v_paid,2),
    case when round((v_meal_cost+v_other)-v_paid,2)>0 then 'due'
         when round((v_meal_cost+v_other)-v_paid,2)<0 then 'advance' else 'settled' end;
end;
$$;

grant execute on function public.get_member_balance(uuid,date,date) to authenticated;
revoke all on function public.get_member_balance(uuid,date,date) from public;

create or replace function public.rebuild_period_ledger(
  p_mess_id uuid,
  p_period_start date,
  p_period_end date
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_rate numeric(14,4);
  r record;
  v_meals numeric;
  v_amount numeric(14,2);
  n integer:=0;
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  if p_period_end < p_period_start then raise exception 'Invalid accounting period'; end if;

  select rate into v_rate from public.calculate_meal_rate(p_mess_id,p_period_start,p_period_end);

  -- Replace only system-generated meal-cost rows for this period.
  delete from public.ledger_entries
  where mess_id=p_mess_id and entry_type='meal_cost' and source='system'
    and entry_date between p_period_start and p_period_end;

  for r in select mm.id as member_id, (mm.activated_at at time zone 'Asia/Dhaka')::date as activated_on,
                  (mm.left_at at time zone 'Asia/Dhaka')::date as left_on
           from public.mess_members mm
           where mm.mess_id=p_mess_id
             and mm.status in ('active','left')
  loop
    select count(*)::numeric into v_meals
    from public.meal_entries me
    where me.member_id=r.member_id and me.meal_date between p_period_start and p_period_end and me.status='on'
      and me.meal_date >= coalesce(r.activated_on,p_period_start)
      and (r.left_on is null or me.meal_date <= r.left_on);

    v_amount:=round(v_meals*coalesce(v_rate,0),2);
    if v_amount<>0 then
      insert into public.ledger_entries(mess_id,member_id,entry_date,entry_type,debit,credit,reference_id,description,source)
      values(p_mess_id,r.member_id,p_period_end,'meal_cost',v_amount,0,null,
             format('Meal cost %s to %s (%s meals × %s)',p_period_start,p_period_end,v_meals,v_rate),'system');
      n:=n+1;
    end if;
  end loop;
  return n;
end;
$$;

grant execute on function public.rebuild_period_ledger(uuid,date,date) to authenticated;
revoke all on function public.rebuild_period_ledger(uuid,date,date) from public;

create or replace function public.record_ledger_adjustment(
  p_mess_member_id uuid,
  p_amount numeric,
  p_entry_type text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v public.mess_members%rowtype;
  v_id uuid;
  v_debit numeric:=0;
  v_credit numeric:=0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.mess_members where id=p_mess_member_id;
  if not found then raise exception 'Member not found'; end if;
  if not public.is_mess_manager(v.mess_id) then raise exception 'Manager permission required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Adjustment amount must be greater than zero'; end if;
  if p_entry_type not in ('adjustment','refund','other_cost') then raise exception 'Invalid ledger adjustment type'; end if;
  if p_entry_type='refund' then v_credit:=p_amount; else v_debit:=p_amount; end if;
  insert into public.ledger_entries(mess_id,member_id,entry_date,entry_type,debit,credit,description,source)
  values(v.mess_id,v.id,current_date,p_entry_type,v_debit,v_credit,nullif(trim(p_description),''),'manual') returning id into v_id;
  insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,new_data)
  values(v.mess_id,auth.uid(),'create','ledger_entry',v_id,jsonb_build_object('entry_type',p_entry_type,'debit',v_debit,'credit',v_credit,'description',p_description));
  return v_id;
end;
$$;

grant execute on function public.record_ledger_adjustment(uuid,numeric,text,text) to authenticated;
revoke all on function public.record_ledger_adjustment(uuid,numeric,text,text) from public;
