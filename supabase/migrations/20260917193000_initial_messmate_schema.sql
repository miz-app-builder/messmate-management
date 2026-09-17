-- MessMate initial schema
-- This migration is the source of truth for the Supabase database.

create type public.mess_member_role as enum ('manager','bazar_manager','member');
create type public.membership_status as enum ('pending','active','rejected','left','removed');
create type public.join_request_status as enum ('pending','approved','rejected','cancelled');
create type public.meal_status as enum ('on','off');
create type public.meal_source as enum ('member','auto','manager');
create type public.bazar_status as enum ('pending','approved','rejected');
create type public.settlement_status as enum ('open','closed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.messes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  description text,
  join_code text not null unique,
  qr_token uuid not null default gen_random_uuid() unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.mess_members (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.mess_member_role not null default 'member',
  status public.membership_status not null default 'pending',
  joined_at timestamptz not null default now(),
  activated_at timestamptz,
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (mess_id, user_id)
);

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status public.join_request_status not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  note text,
  unique (mess_id, user_id)
);

create table public.member_permissions (
  id uuid primary key default gen_random_uuid(),
  mess_member_id uuid not null unique references public.mess_members(id) on delete cascade,
  can_add_bazar boolean not null default false,
  can_approve_bazar boolean not null default false,
  can_add_expense boolean not null default false,
  can_record_deposit boolean not null default false,
  can_manage_meals boolean not null default false,
  can_view_reports boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.mess_settings (
  mess_id uuid primary key references public.messes(id) on delete cascade,
  default_unconfirmed_meal boolean not null default true,
  cutoff_mode text not null default 'same' check (cutoff_mode in ('same','individual')),
  global_cutoff_time time,
  allow_guest_meals boolean not null default true,
  allow_member_meal_edit boolean not null default true,
  manager_override_locked_meal boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.meal_types (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  meal_time time,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (mess_id, name)
);

create table public.meal_cutoff_settings (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  meal_type_id uuid not null unique references public.meal_types(id) on delete cascade,
  cutoff_time time not null,
  default_unconfirmed_meal boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.meal_entries (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  member_id uuid not null references public.mess_members(id) on delete cascade,
  meal_type_id uuid not null references public.meal_types(id) on delete cascade,
  meal_date date not null,
  status public.meal_status not null default 'on',
  source public.meal_source not null default 'member',
  is_locked boolean not null default false,
  cutoff_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (member_id, meal_type_id, meal_date)
);

create table public.meal_off (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  member_id uuid not null references public.mess_members(id) on delete cascade,
  meal_type_id uuid not null references public.meal_types(id) on delete cascade,
  meal_date date not null,
  reason text,
  created_at timestamptz not null default now(),
  unique (member_id, meal_type_id, meal_date)
);

create table public.bazar_entries (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  buyer_member_id uuid not null references public.mess_members(id),
  purchased_on date not null default current_date,
  total_amount numeric(12,2) not null check (total_amount >= 0),
  status public.bazar_status not null default 'pending',
  note text,
  receipt_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id)
);

create table public.bazar_items (
  id uuid primary key default gen_random_uuid(),
  bazar_entry_id uuid not null references public.bazar_entries(id) on delete cascade,
  item_name text not null,
  quantity numeric(12,3),
  unit text,
  amount numeric(12,2) not null check (amount >= 0),
  created_at timestamptz not null default now()
);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (mess_id, name)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  category_id uuid references public.expense_categories(id),
  amount numeric(12,2) not null check (amount >= 0),
  expense_date date not null default current_date,
  description text,
  bazar_entry_id uuid references public.bazar_entries(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.deposits (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  member_id uuid not null references public.mess_members(id),
  amount numeric(12,2) not null check (amount > 0),
  deposited_on date not null default current_date,
  payment_method text,
  note text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  member_id uuid not null references public.mess_members(id),
  entry_date date not null default current_date,
  entry_type text not null check (entry_type in ('deposit','meal_cost','other_cost','adjustment','refund')),
  debit numeric(12,2) not null default 0 check (debit >= 0),
  credit numeric(12,2) not null default 0 check (credit >= 0),
  reference_id uuid,
  description text,
  created_at timestamptz not null default now()
);

create table public.meal_rates (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  period_start date not null,
  period_end date,
  food_cost numeric(12,2) not null default 0,
  total_meals numeric(12,2) not null default 0,
  rate numeric(12,4) not null default 0,
  created_at timestamptz not null default now(),
  unique (mess_id, period_start)
);

create table public.monthly_settlements (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid not null references public.messes(id) on delete cascade,
  member_id uuid not null references public.mess_members(id),
  month_start date not null,
  month_end date not null,
  total_meals numeric(12,2) not null default 0,
  meal_cost numeric(12,2) not null default 0,
  other_cost numeric(12,2) not null default 0,
  total_paid numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  status public.settlement_status not null default 'open',
  closed_at timestamptz,
  closed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (mess_id, member_id, month_start)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mess_id uuid references public.messes(id) on delete cascade,
  title text not null,
  body text,
  type text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  mess_id uuid references public.messes(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index idx_mess_members_user on public.mess_members(user_id);
create index idx_mess_members_mess_status on public.mess_members(mess_id, status);
create index idx_join_requests_mess_status on public.join_requests(mess_id, status);
create index idx_meal_entries_mess_date on public.meal_entries(mess_id, meal_date);
create index idx_meal_entries_member_date on public.meal_entries(member_id, meal_date);
create index idx_bazar_entries_mess_date on public.bazar_entries(mess_id, purchased_on);
create index idx_expenses_mess_date on public.expenses(mess_id, expense_date);
create index idx_deposits_member_date on public.deposits(member_id, deposited_on);
create index idx_ledger_member_date on public.ledger_entries(member_id, entry_date);

create or replace function public.is_mess_member(p_mess_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.mess_members mm where mm.mess_id = p_mess_id and mm.user_id = auth.uid() and mm.status = 'active'); $$;

create or replace function public.is_mess_manager(p_mess_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.mess_members mm where mm.mess_id = p_mess_id and mm.user_id = auth.uid() and mm.status = 'active' and mm.role = 'manager'); $$;

create or replace function public.has_mess_permission(p_mess_id uuid, p_permission text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.mess_members mm
    join public.member_permissions mp on mp.mess_member_id = mm.id
    where mm.mess_id = p_mess_id and mm.user_id = auth.uid() and mm.status = 'active'
      and ((p_permission = 'can_add_bazar' and mp.can_add_bazar)
        or (p_permission = 'can_approve_bazar' and (mp.can_approve_bazar or mm.role in ('manager','bazar_manager')))
        or (p_permission = 'can_add_expense' and mp.can_add_expense)
        or (p_permission = 'can_record_deposit' and mp.can_record_deposit)
        or (p_permission = 'can_manage_meals' and mp.can_manage_meals)
        or (p_permission = 'can_view_reports' and mp.can_view_reports))
  );
$$;

create or replace function public.handle_new_mess()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.mess_members (mess_id,user_id,role,status,activated_at) values (new.id,new.created_by,'manager','active',now());
  insert into public.mess_settings (mess_id) values (new.id);
  insert into public.meal_types (mess_id,name,sort_order,meal_time) values
    (new.id,'Breakfast',1,'08:00'),(new.id,'Lunch',2,'13:30'),(new.id,'Dinner',3,'20:30');
  return new;
end; $$;
create trigger trg_new_mess after insert on public.messes for each row execute function public.handle_new_mess();

create or replace function public.handle_new_member_permissions()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.member_permissions (mess_member_id,can_approve_bazar,can_view_reports)
  values (new.id,new.role in ('manager','bazar_manager'),new.role='manager');
  return new;
end; $$;
create trigger trg_new_member_permissions after insert on public.mess_members for each row execute function public.handle_new_member_permissions();

alter table public.profiles enable row level security;
alter table public.messes enable row level security;
alter table public.mess_members enable row level security;
alter table public.join_requests enable row level security;
alter table public.member_permissions enable row level security;
alter table public.mess_settings enable row level security;
alter table public.meal_types enable row level security;
alter table public.meal_cutoff_settings enable row level security;
alter table public.meal_entries enable row level security;
alter table public.meal_off enable row level security;
alter table public.bazar_entries enable row level security;
alter table public.bazar_items enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.deposits enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.meal_rates enable row level security;
alter table public.monthly_settlements enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select_own on public.profiles for select to authenticated using (id=auth.uid());
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id=auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy messes_select_member on public.messes for select to authenticated using (public.is_mess_member(id) or created_by=auth.uid());
create policy messes_insert_authenticated on public.messes for insert to authenticated with check (created_by=auth.uid());
create policy messes_update_manager on public.messes for update to authenticated using (public.is_mess_manager(id)) with check (public.is_mess_manager(id));
create policy members_select_same_mess on public.mess_members for select to authenticated using (user_id=auth.uid() or public.is_mess_member(mess_id));
create policy members_update_manager on public.mess_members for update to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy join_requests_insert_own on public.join_requests for insert to authenticated with check (user_id=auth.uid() and not public.is_mess_member(mess_id));
create policy join_requests_select_requester_or_manager on public.join_requests for select to authenticated using (user_id=auth.uid() or public.is_mess_manager(mess_id));
create policy join_requests_update_manager on public.join_requests for update to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy permissions_select_own_or_manager on public.member_permissions for select to authenticated using (exists(select 1 from public.mess_members mm where mm.id=mess_member_id and (mm.user_id=auth.uid() or public.is_mess_manager(mm.mess_id))));
create policy permissions_update_manager on public.member_permissions for update to authenticated using (exists(select 1 from public.mess_members mm where mm.id=mess_member_id and public.is_mess_manager(mm.mess_id))) with check (exists(select 1 from public.mess_members mm where mm.id=mess_member_id and public.is_mess_manager(mm.mess_id)));
create policy settings_select_member on public.mess_settings for select to authenticated using (public.is_mess_member(mess_id));
create policy settings_update_manager on public.mess_settings for update to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy meal_types_select_member on public.meal_types for select to authenticated using (public.is_mess_member(mess_id));
create policy meal_types_manage_manager on public.meal_types for all to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy cutoff_select_member on public.meal_cutoff_settings for select to authenticated using (public.is_mess_member(mess_id));
create policy cutoff_manage_manager on public.meal_cutoff_settings for all to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy meals_select_member on public.meal_entries for select to authenticated using (public.is_mess_member(mess_id));
create policy meals_insert_self_or_manager on public.meal_entries for insert to authenticated with check (public.is_mess_member(mess_id) and (exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()) or public.is_mess_manager(mess_id)));
create policy meals_update_self_or_manager on public.meal_entries for update to authenticated using (public.is_mess_member(mess_id) and (public.is_mess_manager(mess_id) or exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()))) with check (public.is_mess_member(mess_id));
create policy meal_off_select_member on public.meal_off for select to authenticated using (public.is_mess_member(mess_id));
create policy meal_off_insert_self on public.meal_off for insert to authenticated with check (public.is_mess_member(mess_id) and exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()));
create policy meal_off_delete_self_or_manager on public.meal_off for delete to authenticated using (public.is_mess_manager(mess_id) or exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()));
create policy bazar_select_member on public.bazar_entries for select to authenticated using (public.is_mess_member(mess_id));
create policy bazar_insert_permission on public.bazar_entries for insert to authenticated with check (public.has_mess_permission(mess_id,'can_add_bazar') and exists(select 1 from public.mess_members mm where mm.id=buyer_member_id and mm.status='active'));
create policy bazar_update_approver on public.bazar_entries for update to authenticated using (public.has_mess_permission(mess_id,'can_approve_bazar')) with check (public.has_mess_permission(mess_id,'can_approve_bazar'));
create policy bazar_items_select_member on public.bazar_items for select to authenticated using (exists(select 1 from public.bazar_entries be where be.id=bazar_entry_id and public.is_mess_member(be.mess_id)));
create policy bazar_items_insert_authorized on public.bazar_items for insert to authenticated with check (exists(select 1 from public.bazar_entries be where be.id=bazar_entry_id and public.has_mess_permission(be.mess_id,'can_add_bazar')));
create policy expense_categories_select_member on public.expense_categories for select to authenticated using (public.is_mess_member(mess_id));
create policy expense_categories_manage_manager on public.expense_categories for all to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy expenses_select_member on public.expenses for select to authenticated using (public.is_mess_member(mess_id));
create policy expenses_insert_permission on public.expenses for insert to authenticated with check (public.has_mess_permission(mess_id,'can_add_expense'));
create policy expenses_update_manager on public.expenses for update to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy deposits_select_member on public.deposits for select to authenticated using (public.is_mess_member(mess_id) and (exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()) or public.is_mess_manager(mess_id)));
create policy deposits_insert_permission on public.deposits for insert to authenticated with check (public.has_mess_permission(mess_id,'can_record_deposit'));
create policy deposits_update_manager on public.deposits for update to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy ledger_select_member on public.ledger_entries for select to authenticated using (public.is_mess_member(mess_id) and (exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()) or public.is_mess_manager(mess_id)));
create policy rates_select_member on public.meal_rates for select to authenticated using (public.is_mess_member(mess_id));
create policy settlements_select_member on public.monthly_settlements for select to authenticated using (public.is_mess_member(mess_id) and (exists(select 1 from public.mess_members mm where mm.id=member_id and mm.user_id=auth.uid()) or public.is_mess_manager(mess_id)));
create policy settlements_manage_manager on public.monthly_settlements for all to authenticated using (public.is_mess_manager(mess_id)) with check (public.is_mess_manager(mess_id));
create policy notifications_select_own on public.notifications for select to authenticated using (user_id=auth.uid());
create policy notifications_update_own on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy audit_select_manager on public.audit_logs for select to authenticated using (public.is_mess_manager(mess_id));
