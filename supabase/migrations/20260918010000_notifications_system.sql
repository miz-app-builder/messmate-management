-- MessMate notifications: in-app event records with safe helper RPC.
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
  if not exists(select 1 from public.mess_members where mess_id=p_mess_id and user_id=p_user_id and status in ('active','pending')) then raise exception 'Notification target is not a mess member'; end if;
  insert into public.notifications(mess_id,user_id,title,message,type,reference_id)
  values(p_mess_id,p_user_id,trim(p_title),trim(p_message),coalesce(p_type,'info'),p_reference_id)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.create_notification(uuid,uuid,text,text,text,uuid) to authenticated;
revoke all on function public.create_notification(uuid,uuid,text,text,text,uuid) from public;

create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);
create index if not exists notifications_mess_created_idx on public.notifications(mess_id,created_at desc);
