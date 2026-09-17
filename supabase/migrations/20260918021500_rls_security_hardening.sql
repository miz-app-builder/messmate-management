-- MessMate RLS security hardening.
-- Sensitive writes are forced through the audited SECURITY DEFINER RPCs.
-- This prevents direct table updates from bypassing cutoff, ownership,
-- approval, immutable-record, and audit requirements.

-- Bazar: creation/review/update must use RPCs; direct update could bypass audit
-- and could mutate approved rows.
drop policy if exists bazar_insert_permission on public.bazar_entries;
drop policy if exists bazar_update_approver on public.bazar_entries;

-- Bazar item creation must use add_bazar_item() so the parent status and
-- ownership rules are enforced consistently.
drop policy if exists bazar_items_insert_authorized on public.bazar_items;

-- Financial records must use their RPCs so audit/void rules cannot be bypassed.
drop policy if exists deposits_insert_permission on public.deposits;
drop policy if exists deposits_update_manager on public.deposits;
drop policy if exists expenses_insert_permission on public.expenses;
drop policy if exists expenses_update_manager on public.expenses;

-- Meal changes must use set_my_meal()/manager_set_meal()/ensure_my_meals().
-- Direct table writes would otherwise bypass cutoff and lock checks.
drop policy if exists meals_insert_self_or_manager on public.meal_entries;
drop policy if exists meals_update_self_or_manager on public.meal_entries;
drop policy if exists meal_off_insert_self on public.meal_off;
drop policy if exists meal_off_delete_self_or_manager on public.meal_off;

-- Settlements are finalized through close_month_for_mess()/create_monthly_settlement().
-- Direct ALL access would permit modification of closed snapshots.
drop policy if exists settlements_manage_manager on public.monthly_settlements;

-- Keep meal privacy member-specific. A member should not be able to read
-- another member's meal choices merely because both belong to the same mess.
drop policy if exists meals_select_member on public.meal_entries;
create policy meals_select_own_or_manager
on public.meal_entries for select to authenticated
using (
  is_mess_member(mess_id)
  and (
    is_mess_manager(mess_id)
    or exists (
      select 1 from public.mess_members mm
      where mm.id=meal_entries.member_id
        and mm.user_id=auth.uid()
    )
  )
);

-- Same privacy rule for meal-off records.
drop policy if exists meal_off_select_member on public.meal_off;
create policy meal_off_select_own_or_manager
on public.meal_off for select to authenticated
using (
  is_mess_member(mess_id)
  and (
    is_mess_manager(mess_id)
    or exists (
      select 1 from public.mess_members mm
      where mm.id=meal_off.member_id
        and mm.user_id=auth.uid()
    )
  )
);

-- Meal rates are mess-wide financial information and remain visible to active
-- members, but pending users must not gain access.
drop policy if exists rates_select_member on public.meal_rates;
create policy rates_select_active_member
on public.meal_rates for select to authenticated
using (is_mess_member(mess_id));

-- Pending users should not read operational mess settings. Active members only.
drop policy if exists settings_member_read on public.mess_settings;
drop policy if exists settings_select_member on public.mess_settings;
create policy settings_select_active_member
on public.mess_settings for select to authenticated
using (is_mess_member(mess_id));

-- Meal cutoff configuration is also active-member only.
drop policy if exists cutoff_select_member on public.meal_cutoff_settings;
create policy cutoff_select_active_member
on public.meal_cutoff_settings for select to authenticated
using (is_mess_member(mess_id));

-- Meal types should likewise be readable only by active members. Remove the
-- duplicate/looser membership policy that allowed pending users to read them.
drop policy if exists meal_types_member_read on public.meal_types;
drop policy if exists meal_types_select_member on public.meal_types;
create policy meal_types_select_active_member
on public.meal_types for select to authenticated
using (is_mess_member(mess_id));

-- Remove duplicate member SELECT policies. Keep one clear rule: a user can
-- see their own membership row or members of a mess where they are active.
drop policy if exists members_select_same_mess on public.mess_members;
drop policy if exists mess_member_read on public.mess_members;
create policy members_select_same_mess
on public.mess_members for select to authenticated
using (user_id=auth.uid() or is_mess_member(mess_id));

-- Permissions: only active managers may read other members' permissions; a
-- member can read only their own permissions.
drop policy if exists permissions_select_own_or_manager on public.member_permissions;
drop policy if exists permissions_self_read on public.member_permissions;
create policy permissions_select_own_or_manager
on public.member_permissions for select to authenticated
using (
  exists (
    select 1 from public.mess_members mm
    where mm.id=member_permissions.mess_member_id
      and (
        mm.user_id=auth.uid()
        or is_mess_manager(mm.mess_id)
      )
  )
);

-- Profiles are intentionally limited to active co-members or the owner.
-- Existing same-mess policy already has that rule; remove duplicate own-only
-- policies so the effective SELECT rule is easier to audit.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_select_own_or_active_mess
on public.profiles for select to authenticated
using (
  id=auth.uid()
  or exists (
    select 1
    from public.mess_members mm
    where mm.user_id=profiles.id
      and mm.status='active'
      and is_mess_member(mm.mess_id)
  )
);

-- Notification writes remain server-side. There is intentionally no INSERT
-- policy for authenticated users; event triggers/cron use SECURITY DEFINER.

-- Audit logs are read-only to managers; no authenticated INSERT/UPDATE/DELETE
-- policy is granted, so audit records cannot be tampered with through PostgREST.
