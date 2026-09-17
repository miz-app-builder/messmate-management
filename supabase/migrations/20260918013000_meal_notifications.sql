-- Meal notification helpers. Run this migration in Supabase SQL Editor.
create or replace function public.notify_meal_events(p_mess_id uuid, p_target_date date default (timezone('Asia/Dhaka',now()))::date)
returns integer
language plpgsql security definer set search_path=public
as $$
declare v_count integer:=0; r record; v_cutoff timestamptz; v_title text; v_message text;
begin
 if auth.uid() is null or not public.is_mess_manager(p_mess_id) then raise exception 'Manager access required'; end if;
 -- Prepare tomorrow's meals for active members so the reminder has concrete entries.
 for r in select me.id,me.member_id,me.meal_type_id,mt.name,me.meal_date,me.cutoff_at,me.is_locked,mm.user_id
   from public.meal_entries me join public.meal_types mt on mt.id=me.meal_type_id
   join public.mess_members mm on mm.id=me.member_id
   where me.mess_id=p_mess_id and mm.status='active' and me.meal_date between p_target_date and p_target_date+1 loop
   if r.meal_date=p_target_date+1 and r.cutoff_at is not null and r.cutoff_at > now() and r.is_locked=false then
     v_title:='Tomorrow meal reminder'; v_message:=r.name||' for tomorrow is currently '||case when exists(select 1 from public.meal_entries x where x.id=r.id and x.status='off') then 'OFF' else 'ON' end||'. Cutoff: '||to_char(r.cutoff_at at time zone 'Asia/Dhaka','HH24:MI');
     if not exists(select 1 from public.notifications n where n.user_id=r.user_id and n.reference_id=r.id and n.type='meal_reminder' and n.created_at::date=(timezone('Asia/Dhaka',now()))::date) then
       insert into public.notifications(user_id,mess_id,title,body,type,created_at) values(r.user_id,p_mess_id,v_title,v_message,'meal_reminder',now()); v_count:=v_count+1;
     end if;
   end if;
   if r.meal_date=p_target_date and r.cutoff_at is not null and r.cutoff_at <= now() and r.is_locked=false then
     update public.meal_entries set is_locked=true,updated_at=now() where id=r.id;
     if not exists(select 1 from public.notifications n where n.user_id=r.user_id and n.reference_id=r.id and n.type='meal_locked') then
       insert into public.notifications(user_id,mess_id,title,body,type,reference_id) values(r.user_id,p_mess_id,r.name||' locked','The cutoff has passed. Your '||lower(r.name)||' entry is now locked.','meal_locked',r.id); v_count:=v_count+1;
     end if;
   end if;
 end loop;
 return v_count;
end;
$$;

grant execute on function public.notify_meal_events(uuid,date) to authenticated;
revoke all on function public.notify_meal_events(uuid,date) from public;
