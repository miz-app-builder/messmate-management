-- MessMate final meal-off hardening
-- Keep meal_off synchronized with the audited meal RPC path.

drop policy if exists meal_off_insert_self on public.meal_off;
drop policy if exists meal_off_delete_self_or_manager on public.meal_off;

-- Validate that cutoff settings cannot be written against another mess's meal type.
create or replace function public.save_meal_cutoff(
  p_mess_id uuid,
  p_meal_type_id uuid,
  p_cutoff_time time,
  p_default_unconfirmed boolean default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_type_mess uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_manager(p_mess_id) then raise exception 'Manager permission required'; end if;
  select mess_id into v_type_mess from public.meal_types where id=p_meal_type_id;
  if v_type_mess is null or v_type_mess<>p_mess_id then raise exception 'Meal type does not belong to this mess'; end if;
  if p_cutoff_time is null then raise exception 'Cut-off time is required'; end if;

  insert into public.meal_cutoff_settings(mess_id,meal_type_id,cutoff_time,default_unconfirmed_meal)
  values(p_mess_id,p_meal_type_id,p_cutoff_time,p_default_unconfirmed)
  on conflict(meal_type_id) do update
    set cutoff_time=excluded.cutoff_time,
        default_unconfirmed_meal=excluded.default_unconfirmed_meal,
        updated_at=now();
end;
$$;

grant execute on function public.save_meal_cutoff(uuid,uuid,time,boolean) to authenticated;
revoke all on function public.save_meal_cutoff(uuid,uuid,time,boolean) from public;

-- Bound the client-controlled generation window to prevent accidental huge writes.
create or replace function public.ensure_my_meals(
  p_mess_id uuid,
  p_start_date date default current_date,
  p_days integer default 2
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_member public.mess_members%rowtype;
  v_count integer := 0;
  d date;
  mt record;
  v_default boolean;
  v_cutoff timestamptz;
  v_days integer := greatest(1,least(coalesce(p_days,2),31));
begin
  select * into v_member from public.mess_members
  where mess_id=p_mess_id and user_id=auth.uid() and status='active' limit 1;
  if not found then raise exception 'Only active members can create meal entries'; end if;

  for d in select generate_series(p_start_date,p_start_date+v_days-1,'1 day')::date loop
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
            is_locked=public.meal_entries.is_locked;
      v_count := v_count+1;
    end loop;
  end loop;
  return v_count;
end;
$$;

grant execute on function public.ensure_my_meals(uuid,date,integer) to authenticated;
revoke all on function public.ensure_my_meals(uuid,date,integer) from public;
