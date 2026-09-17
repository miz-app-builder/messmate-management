-- MessMate notification/cron repair.
-- Aligns notification helpers with the actual notifications schema (body, no reference_id)
-- and gives cron a service-safe worker path without relying on auth.uid().

create or replace function public.create_notification(
  p_mess_id uuid,
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text default 'info',
  p_reference_id uuid default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_mess_member(p_mess_id) then raise exception 'Not authorized'; end if;
  if not exists (
    select 1 from public.mess_members
    where mess_id=p_mess_id and user_id=p_user_id and status in ('active','pending')
  ) then raise exception 'Notification target is not a mess member'; end if;

  insert into public.notifications(user_id,mess_id,title,body,type)
  values(p_user_id,p_mess_id,trim(p_title),trim(p_message),coalesce(p_type,'info'))
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.create_notification(uuid,uuid,text,text,text,uuid) to authenticated;
revoke all on function public.create_notification(uuid,uuid,text,text,text,uuid) from public;

-- Internal worker: intentionally has no auth.uid() dependency because pg_cron runs
-- outside a logged-in user session. It is only called by the locked-down cron wrapper.
create or replace function public.process_messmate_meal_notifications(
  p_mess_id uuid,
  p_target_date date default (timezone('Asia/Dhaka',now()))::date
)
returns integer
language plpgsql security definer set search_path=public
as $$
declare
  v_count integer:=0;
  r record;
  v_message text;
begin
  for r in
    select me.id, me.member_id, mt.name, me.meal_date, me.cutoff_at, me.is_locked,
           me.status, mm.user_id
    from public.meal_entries me
    join public.meal_types mt on mt.id=me.meal_type_id
    join public.mess_members mm on mm.id=me.member_id
    where me.mess_id=p_mess_id
      and mm.status='active'
      and me.meal_date between p_target_date and p_target_date+1
  loop
    -- Tomorrow reminder: one reminder per member/meal/date/day.
    if r.meal_date=p_target_date+1 and r.cutoff_at is not null
       and r.cutoff_at > now() and r.is_locked=false then
      v_message:=r.name || ' for tomorrow is currently ' ||
        case when r.status='off' then 'OFF' else 'ON' end ||
        '. Cutoff: ' || to_char(r.cutoff_at at time zone 'Asia/Dhaka','HH24:MI');

      if not exists (
        select 1 from public.notifications n
        where n.user_id=r.user_id and n.mess_id=p_mess_id
          and n.type='meal_reminder'
          and n.title='Tomorrow meal reminder'
          and n.body=v_message
          and n.created_at::date=(timezone('Asia/Dhaka',now()))::date
      ) then
        insert into public.notifications(user_id,mess_id,title,body,type,created_at)
        values(r.user_id,p_mess_id,'Tomorrow meal reminder',v_message,'meal_reminder',now());
        v_count:=v_count+1;
      end if;
    end if;

    -- Lock overdue entries. The meal entry already carries its default/selected status.
    if r.meal_date=p_target_date and r.cutoff_at is not null
       and r.cutoff_at <= now() and r.is_locked=false then
      update public.meal_entries
      set is_locked=true, updated_at=now()
      where id=r.id and is_locked=false;

      if not exists (
        select 1 from public.notifications n
        where n.user_id=r.user_id and n.mess_id=p_mess_id
          and n.type='meal_locked'
          and n.title=r.name || ' locked'
          and n.body='The cutoff has passed. Your ' || lower(r.name) || ' entry is now locked.'
      ) then
        insert into public.notifications(user_id,mess_id,title,body,type,created_at)
        values(
          r.user_id,p_mess_id,r.name || ' locked',
          'The cutoff has passed. Your ' || lower(r.name) || ' entry is now locked.',
          'meal_locked',now()
        );
        v_count:=v_count+1;
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.process_messmate_meal_notifications(uuid,date) from public,authenticated;
grant execute on function public.process_messmate_meal_notifications(uuid,date) to service_role;

-- Keep the authenticated/manual helper manager-only, but delegate to the internal worker.
create or replace function public.notify_meal_events(
  p_mess_id uuid,
  p_target_date date default (timezone('Asia/Dhaka',now()))::date
)
returns integer
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_mess_manager(p_mess_id) then
    raise exception 'Manager access required';
  end if;
  return public.process_messmate_meal_notifications(p_mess_id,p_target_date);
end;
$$;

grant execute on function public.notify_meal_events(uuid,date) to authenticated;
revoke all on function public.notify_meal_events(uuid,date) from public;

-- Cron wrapper must call the internal worker, not the manager-only wrapper.
create or replace function public.run_messmate_meal_notifications()
returns integer
language plpgsql security definer set search_path=public
as $$
declare r record; v_total integer:=0;
begin
  for r in select id from public.messes loop
    begin
      v_total:=v_total+coalesce(
        public.process_messmate_meal_notifications(r.id,(timezone('Asia/Dhaka',now()))::date),0
      );
    exception when others then
      -- One broken mess must not prevent other messes from being processed.
      null;
    end;
  end loop;
  return v_total;
end;
$$;

grant execute on function public.run_messmate_meal_notifications() to service_role;
revoke all on function public.run_messmate_meal_notifications() from public,authenticated;

-- Remove the redundant second job if it exists; the 15-minute worker already
-- creates tomorrow reminders with a same-day duplicate guard.
select cron.unschedule(jobid)
from cron.job
where jobname='messmate-tomorrow-meal-reminder';

select cron.schedule('messmate-meal-events','*/15 * * * *',
  $$select public.run_messmate_meal_notifications();$$)
where not exists (
  select 1 from cron.job where jobname='messmate-meal-events'
);
