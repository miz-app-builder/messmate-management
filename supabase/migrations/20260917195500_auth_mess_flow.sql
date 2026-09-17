-- Auth, create-mess and join-request foundation.
-- All privileged writes go through SECURITY DEFINER RPCs with explicit auth checks.

create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.phone)
  on conflict (id) do update
    set full_name = coalesce(excluded.full_name, public.profiles.full_name),
        phone = coalesce(excluded.phone, public.profiles.phone),
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_profile();

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
declare
  v_mess_id uuid;
  v_code text;
  v_member_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'Mess name is required'; end if;

  v_code := upper(regexp_replace(coalesce(nullif(trim(p_join_code), ''), substr(encode(gen_random_bytes(5), 'hex'), 1, 8)), '[^A-Z0-9]', '', 'g'));
  if length(v_code) < 6 then v_code := v_code || substr(encode(gen_random_bytes(5), 'hex'), 1, 6); end if;

  insert into public.messes (name, address, description, join_code, created_by)
  values (trim(p_name), nullif(trim(p_address), ''), nullif(trim(p_description), ''), v_code, auth.uid())
  returning id into v_mess_id;

  insert into public.mess_members (mess_id, user_id, role, status, activated_at)
  values (v_mess_id, auth.uid(), 'manager', 'active', now())
  returning id into v_member_id;

  insert into public.member_permissions (mess_member_id, can_add_bazar, can_approve_bazar, can_add_expense, can_record_deposit, can_manage_meals, can_view_reports)
  values (v_member_id, true, true, true, true, true, true);

  insert into public.mess_settings (mess_id, global_cutoff_time) values (v_mess_id, '22:00');
  insert into public.meal_types (mess_id, name, sort_order, meal_time) values
    (v_mess_id, 'Breakfast', 1, '08:00'),
    (v_mess_id, 'Lunch', 2, '13:30'),
    (v_mess_id, 'Dinner', 3, '20:30');

  return v_mess_id;
exception when unique_violation then
  raise exception 'That join code is already in use. Please try again.';
end;
$$;

grant execute on function public.create_mess(text,text,text,text) to authenticated;

create or replace function public.request_join_mess(p_join_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mess public.messes%rowtype;
  v_request_id uuid;
  v_existing public.mess_members%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_mess from public.messes where join_code = upper(trim(p_join_code));
  if v_mess.id is null then raise exception 'Mess code not found'; end if;

  select * into v_existing from public.mess_members where mess_id = v_mess.id and user_id = auth.uid();
  if v_existing.id is not null and v_existing.status = 'active' then raise exception 'You are already an active member'; end if;
  if v_existing.id is not null and v_existing.status = 'pending' then raise exception 'Your join request is already pending'; end if;

  insert into public.join_requests (mess_id, user_id, status)
  values (v_mess.id, auth.uid(), 'pending')
  on conflict (mess_id, user_id) do update set status='pending', requested_at=now(), reviewed_at=null, reviewed_by=null
  returning id into v_request_id;

  insert into public.mess_members (mess_id, user_id, role, status)
  values (v_mess.id, auth.uid(), 'member', 'pending')
  on conflict (mess_id, user_id) do update set status='pending', role='member', updated_at=now();

  return v_request_id;
end;
$$;

grant execute on function public.request_join_mess(text) to authenticated;

create or replace function public.review_join_request(p_request_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.join_requests%rowtype;
  v_manager boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select exists (
    select 1 from public.mess_members mm
    where mm.mess_id = (select mess_id from public.join_requests where id=p_request_id)
      and mm.user_id = auth.uid() and mm.role='manager' and mm.status='active'
  ) into v_manager;
  if not v_manager then raise exception 'Manager permission required'; end if;

  select * into v_request from public.join_requests where id=p_request_id for update;
  if v_request.id is null or v_request.status <> 'pending' then raise exception 'Join request is not pending'; end if;

  update public.join_requests
    set status = case when p_approve then 'approved'::public.join_request_status else 'rejected'::public.join_request_status end,
        reviewed_at = now(), reviewed_by = auth.uid(), note = nullif(trim(p_note), '')
    where id = p_request_id;

  update public.mess_members
    set status = case when p_approve then 'active'::public.membership_status else 'rejected'::public.membership_status end,
        activated_at = case when p_approve then now() else null end,
        updated_at = now()
    where mess_id=v_request.mess_id and user_id=v_request.user_id;

  if p_approve then
    insert into public.member_permissions (mess_member_id)
    select id from public.mess_members where mess_id=v_request.mess_id and user_id=v_request.user_id
    on conflict (mess_member_id) do nothing;
  end if;
end;
$$;

grant execute on function public.review_join_request(uuid,boolean,text) to authenticated;

-- Basic read policies. Writes for privileged flows remain RPC-controlled.
alter table public.profiles enable row level security;
alter table public.messes enable row level security;
alter table public.mess_members enable row level security;
alter table public.join_requests enable row level security;
alter table public.member_permissions enable row level security;
alter table public.mess_settings enable row level security;
alter table public.meal_types enable row level security;

create policy profiles_self_read on public.profiles for select to authenticated using (id=auth.uid());
create policy mess_member_read on public.mess_members for select to authenticated using (user_id=auth.uid());
create policy join_request_self_read on public.join_requests for select to authenticated using (user_id=auth.uid());
create policy mess_read_for_member on public.messes for select to authenticated using (exists (select 1 from public.mess_members mm where mm.mess_id=messes.id and mm.user_id=auth.uid()));
create policy permissions_self_read on public.member_permissions for select to authenticated using (exists (select 1 from public.mess_members mm where mm.id=member_permissions.mess_member_id and mm.user_id=auth.uid()));
create policy settings_member_read on public.mess_settings for select to authenticated using (exists (select 1 from public.mess_members mm where mm.mess_id=mess_settings.mess_id and mm.user_id=auth.uid()));
create policy meal_types_member_read on public.meal_types for select to authenticated using (exists (select 1 from public.mess_members mm where mm.mess_id=meal_types.mess_id and mm.user_id=auth.uid()));
