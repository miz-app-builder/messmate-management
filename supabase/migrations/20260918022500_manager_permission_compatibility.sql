-- MessMate manager permission compatibility
-- Managers are implicit full-permission actors. Keep member_permissions as
-- the grant mechanism for delegated members, while managers retain access
-- to all permission-gated RPCs.

create or replace function public.has_mess_permission(p_mess_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_mess_manager(p_mess_id)
    or exists (
      select 1
      from public.mess_members mm
      join public.member_permissions mp on mp.mess_member_id = mm.id
      where mm.mess_id = p_mess_id
        and mm.user_id = auth.uid()
        and mm.status = 'active'
        and (
          (p_permission = 'can_add_bazar' and mp.can_add_bazar)
          or (p_permission = 'can_approve_bazar' and (mp.can_approve_bazar or mm.role in ('manager','bazar_manager')))
          or (p_permission = 'can_add_expense' and mp.can_add_expense)
          or (p_permission = 'can_record_deposit' and mp.can_record_deposit)
          or (p_permission = 'can_manage_meals' and mp.can_manage_meals)
          or (p_permission = 'can_view_reports' and mp.can_view_reports)
        )
    );
$$;

grant execute on function public.has_mess_permission(uuid,text) to authenticated;
revoke execute on function public.has_mess_permission(uuid,text) from public;
