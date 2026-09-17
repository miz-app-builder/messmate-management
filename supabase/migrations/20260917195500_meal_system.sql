-- MessMate meal engine
-- Secure member/manager meal updates, cut-off locking, defaults and meal-off scheduling.

create or replace function public.meal_cutoff_for(p_mess_id uuid, p_meal_type_id uuid, p_meal_date date)
returns timestamptz
language sql stable security definer set search_path = public
as $$
  select make_timestamptz(
    extract(year from p_meal_date)::int,
    extract(month from p_meal_date)::int,
    extract(day from p_meal_date)::int,
    extract(hour from coalesce(mcs.cutoff_time, ms.global_cutoff_time, '22:00'::time))::int,
    extract(minute from coalesce(mcs.cutoff_time, ms.global_cutoff_time, '00:00'::time))::int,
    extract(second from coalesce(mcs.cutoff_time, ms.global_cutoff_time, '00:00'::time)),
    'Asia/Dhaka'
  )
  from public.mess_settings ms
  left join public.meal_cutoff_settings mcs
    on mcs.mess_id = p_mess_id and mcs.meal_type_id = p_meal_type_id
  where ms.mess_id = p_mess_id;
$$;

create or replace function public.ensure_my_meals(p_mess_id uuid, p_start_date date default current_date, p_days integer default 2)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_member public.mess_members%rowtype;
  v_count integer := 0;
  d date;
  mt record;
  v_default boolean;
  v_cutoff timestamptz;
begin
  select * into v_member from public.mess_members
  where mess_id=p_mess_id and user_id=auth.uid() and status='active' limit 1;
  if not found then raise exception 'Only active members can create meal entries'; end if;

  for d in select generate_series(p_start_date,p_start_date+greatest(p_days-1,0),'1 day')::date loop
    for mt in select * from public.meal_types where mess_id=p_mess_id and is_active=true order by sort_order loop
      select coalesce(mcs.default_unconfirmed_meal, ms.default_unconfirmed_meal, true)
        into v_default
      from public.mess_settings ms
      left join public.meal_cutoff_settings mcs on mcs.mess_id=ms.mess_id and mcs.meal_type_id=mt.id
      where ms.mess_id=p_mess_id;
      v_cutoff := public.meal_cutoff_for(p_mess_id,mt.id,d);
      insert into public.meal_entries(mess_id,member_id,meal_type_id,meal_date,status,source,is_locked,cutoff_at)
      values(p_mess_id,v_member.id,mt.id,d,case when v_default then 'on' else 'off' end,'auto',false,v_cutoff)
      on conflict(member_id,meal_type_id,meal_date) do update
        set cutoff_at=excluded.cutoff_at,
            is_locked=case when public.meal_entries.is_locked then true else public.meal_entries.is_locked end;
      v_count := v_count+1;
    end loop;
  end loop;
  return v_count;
end;
$$;

create or replace function public.set_my_meal(p_mess_id uuid, p_meal_type_id uuid, p_meal_date date, p_status public.meal_status)
returns public.meal_entries
language plpgsql security definer set search_path = public
as $$
declare
  v_member public.mess_members%rowtype;
  v_entry public.meal_entries%rowtype;
  v_cutoff timestamptz;
begin
  select * into v_member from public.mess_members where mess_id=p_mess_id and user_id=auth.uid() and status='active' limit 1;
  if not found then raise exception 'Only active members can change meals'; end if;
  perform public.ensure_my_meals(p_mess_id,p_meal_date,1);
  select * into v_entry from public.meal_entries where member_id=v_member.id and meal_type_id=p_meal_type_id and meal_date=p_meal_date;
  v_cutoff := coalesce(v_entry.cutoff_at,public.meal_cutoff_for(p_mess_id,p_meal_type_id,p_meal_date));
  if now() >= v_cutoff then raise exception 'Meal is locked after cut-off'; end if;
  update public.meal_entries set status=p_status,source='member',updated_at=now() where id=v_entry.id returning * into v_entry;
  if p_status='off' then
    insert into public.meal_off(mess_id,member_id,meal_type_id,meal_date,reason)
    values(p_mess_id,v_member.id,p_meal_type_id,p_meal_date,'Member meal off')
    on conflict(member_id,meal_type_id,meal_date) do nothing;
  else
    delete from public.meal_off where member_id=v_member.id and meal_type_id=p_meal_type_id and meal_date=p_meal_date;
  end if;
  return v_entry;
end;
$$;

create or replace function public.finalize_due_meals(p_mess_id uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  r record; n integer := 0;
begin
  if not public.is_mess_member(p_mess_id) then raise exception 'Not an active mess member'; end if;
  for r in select me.id,me.status,me.is_locked,me.cutoff_at,me.member_id,me.meal_type_id,me.meal_date
           from public.meal_entries me where me.mess_id=p_mess_id and me.is_locked=false loop
    if r.cutoff_at is not null and now() >= r.cutoff_at then
      update public.meal_entries set is_locked=true,source=case when source='member' then source else 'auto' end,updated_at=now() where id=r.id;
      n:=n+1;
    end if;
  end loop;
  return n;
end;
$$;

create or replace function public.manager_set_meal(p_entry_id uuid,p_status public.meal_status,p_reason text default null)
returns public.meal_entries
language plpgsql security definer set search_path = public
as $$
declare r public.meal_entries%rowtype; old jsonb;
begin
  select * into r from public.meal_entries where id=p_entry_id;
  if not found or not public.is_mess_manager(r.mess_id) then raise exception 'Manager permission required'; end if;
  old:=to_jsonb(r);
  update public.meal_entries set status=p_status,source='manager',is_locked=true,updated_at=now() where id=p_entry_id returning * into r;
  insert into public.audit_logs(mess_id,actor_user_id,entity_type,entity_id,action,old_data,new_data)
  values(r.mess_id,auth.uid(),'meal_entry',r.id,'manager_override',old,to_jsonb(r)||jsonb_build_object('reason',p_reason));
  return r;
end;
$$;

create or replace function public.save_meal_cutoff(p_mess_id uuid,p_meal_type_id uuid,p_cutoff_time time,p_default_unconfirmed boolean default null)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  insert into public.meal_cutoff_settings(mess_id,meal_type_id,cutoff_time,default_unconfirmed_meal)
  values(p_mess_id,p_meal_type_id,p_cutoff_time,p_default_unconfirmed)
  on conflict(meal_type_id) do update set cutoff_time=excluded.cutoff_time,default_unconfirmed_meal=excluded.default_unconfirmed_meal,updated_at=now();
end;
$$;

revoke all on function public.meal_cutoff_for(uuid,uuid,date) from public;
revoke all on function public.ensure_my_meals(uuid,date,integer) from public;
revoke all on function public.set_my_meal(uuid,uuid,date,public.meal_status) from public;
revoke all on function public.finalize_due_meals(uuid) from public;
revoke all on function public.manager_set_meal(uuid,public.meal_status,text) from public;
revoke all on function public.save_meal_cutoff(uuid,uuid,time,boolean) from public;
grant execute on function public.meal_cutoff_for(uuid,uuid,date) to authenticated;
grant execute on function public.ensure_my_meals(uuid,date,integer) to authenticated;
grant execute on function public.set_my_meal(uuid,uuid,date,public.meal_status) to authenticated;
grant execute on function public.finalize_due_meals(uuid) to authenticated;
grant execute on function public.manager_set_meal(uuid,public.meal_status,text) to authenticated;
grant execute on function public.save_meal_cutoff(uuid,uuid,time,boolean) to authenticated;
