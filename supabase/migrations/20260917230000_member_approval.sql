-- MessMate member approval workflow

create or replace function public.create_mess(
  p_name text,
  p_address text default null,
  p_description text default null,
  p_join_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_mess_id uuid; v_code text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Mess name is required'; end if;
  v_code := upper(nullif(trim(p_join_code),''));
  if v_code is null then
    v_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,8));
  end if;
  insert into public.messes(name,address,description,join_code,created_by)
  values(trim(p_name),nullif(trim(p_address),''),p_description,v_code,auth.uid())
  returning id into v_mess_id;
  return v_mess_id;
exception when unique_violation then
  raise exception 'That join code is already in use. Choose another code.';
end; $$;

grant execute on function public.create_mess(text,text,text,text) to authenticated;

create or replace function public.request_join_mess(p_join_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_mess public.messes%rowtype; v_member uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_mess from public.messes where upper(join_code)=upper(trim(p_join_code));
  if not found then raise exception 'Mess code not found'; end if;
  if exists(select 1 from public.mess_members where mess_id=v_mess.id and user_id=auth.uid() and status='active') then raise exception 'You are already an active member of this mess'; end if;
  insert into public.mess_members(mess_id,user_id,role,status) values(v_mess.id,auth.uid(),'member','pending')
  on conflict (mess_id,user_id) do update set status='pending', joined_at=now(), left_at=null;
  select id into v_member from public.mess_members where mess_id=v_mess.id and user_id=auth.uid();
  insert into public.join_requests(mess_id,user_id,status) values(v_mess.id,auth.uid(),'pending')
  on conflict (mess_id,user_id) do update set status='pending', requested_at=now(), reviewed_at=null, reviewed_by=null;
  insert into public.notifications(user_id,mess_id,title,body,type)
  values(v_mess.created_by,v_mess.id,'New join request',coalesce((select full_name from public.profiles where id=auth.uid()),'A member')||' requested to join your mess.','join_request');
  return v_member;
end; $$;

grant execute on function public.request_join_mess(text) to authenticated;

create or replace function public.review_join_request(p_request_id uuid, p_decision text, p_note text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare r public.join_requests%rowtype; m public.mess_members%rowtype; v_name text;
begin
  select * into r from public.join_requests where id=p_request_id for update;
  if not found then raise exception 'Join request not found'; end if;
  if not public.is_mess_manager(r.mess_id) then raise exception 'Manager permission required'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  if lower(p_decision) not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into m from public.mess_members where mess_id=r.mess_id and user_id=r.user_id for update;
  select coalesce(full_name,'Member') into v_name from public.profiles where id=r.user_id;
  if lower(p_decision)='approved' then
    update public.mess_members set status='active', role='member', activated_at=coalesce(activated_at,now()), left_at=null, updated_at=now() where id=m.id;
    update public.join_requests set status='approved', reviewed_at=now(), reviewed_by=auth.uid(), note=p_note where id=r.id;
    insert into public.notifications(user_id,mess_id,title,body,type) values(r.user_id,r.mess_id,'Join request approved','Your request to join the mess was approved. You are now an active member.','join_approved');
    insert into public.audit_logs(mess_id,actor_user_id,entity_type,entity_id,action,old_data,new_data) values(r.mess_id,auth.uid(),'join_request',r.id,'approved',jsonb_build_object('status','pending'),jsonb_build_object('status','active','member_id',m.id));
  else
    update public.mess_members set status='rejected', updated_at=now() where id=m.id;
    update public.join_requests set status='rejected', reviewed_at=now(), reviewed_by=auth.uid(), note=p_note where id=r.id;
    insert into public.notifications(user_id,mess_id,title,body,type) values(r.user_id,r.mess_id,'Join request rejected','Your request to join the mess was rejected.', 'join_rejected');
    insert into public.audit_logs(mess_id,actor_user_id,entity_type,entity_id,action,old_data,new_data) values(r.mess_id,auth.uid(),'join_request',r.id,'rejected',jsonb_build_object('status','pending'),jsonb_build_object('status','rejected'));
  end if;
  return true;
end; $$;

grant execute on function public.review_join_request(uuid,text,text) to authenticated;

create policy profiles_select_same_mess on public.profiles
for select to authenticated
using (id=auth.uid() or exists(select 1 from public.mess_members mm where mm.user_id=profiles.id and mm.status='active' and public.is_mess_member(mm.mess_id)));
