-- MessMate security hardening
-- Keep sensitive financial/meal state changes behind audited RPCs.

-- Direct table UPDATE/INSERT paths can bypass RPC validation/audit, so remove
-- those broad policies and expose the intended RPCs instead.
drop policy if exists bazar_update_approver on public.bazar_entries;
drop policy if exists bazar_insert_permission on public.bazar_entries;
drop policy if exists bazar_items_insert_authorized on public.bazar_items;
drop policy if exists expenses_insert_permission on public.expenses;
drop policy if exists expenses_update_manager on public.expenses;
drop policy if exists deposits_insert_permission on public.deposits;
drop policy if exists deposits_update_manager on public.deposits;
drop policy if exists meals_insert_self_or_manager on public.meal_entries;
drop policy if exists meals_update_self_or_manager on public.meal_entries;

-- Preserve read access through existing SELECT policies. Meal writes are done
-- by ensure_my_meals/set_my_meal/manager_set_meal; finance and bazar writes
-- are done by their SECURITY DEFINER RPCs.

-- Ensure RPC functions cannot be called anonymously.
revoke all on function public.create_bazar_entry(uuid,date,numeric,text,text) from public;
revoke all on function public.review_bazar_entry(uuid,public.bazar_status,text) from public;
revoke all on function public.update_bazar_entry(uuid,date,numeric,text,text) from public;
revoke all on function public.set_bazar_approval_required(uuid,boolean) from public;
revoke all on function public.add_bazar_item(uuid,text,numeric,text,numeric) from public;
revoke all on function public.delete_bazar_item(uuid) from public;
revoke all on function public.recalculate_bazar_entry_total(uuid) from public;
revoke all on function public.create_bazar_entry_with_items(uuid,date,text,text,jsonb) from public;
revoke all on function public.create_expense(uuid,uuid,numeric,date,text,text) from public;
revoke all on function public.update_expense(uuid,uuid,numeric,date,text,text) from public;
revoke all on function public.void_expense(uuid,text) from public;
revoke all on function public.create_deposit(uuid,uuid,numeric,date,text,text) from public;
revoke all on function public.void_deposit(uuid,text) from public;
revoke all on function public.ensure_my_meals(uuid,date,integer) from public;
revoke all on function public.set_my_meal(uuid,uuid,date,public.meal_status) from public;
revoke all on function public.finalize_due_meals(uuid) from public;
revoke all on function public.manager_set_meal(uuid,public.meal_status,text) from public;
revoke all on function public.save_meal_cutoff(uuid,uuid,time,boolean) from public;

grant execute on function public.create_bazar_entry(uuid,date,numeric,text,text) to authenticated;
grant execute on function public.review_bazar_entry(uuid,public.bazar_status,text) to authenticated;
grant execute on function public.update_bazar_entry(uuid,date,numeric,text,text) to authenticated;
grant execute on function public.set_bazar_approval_required(uuid,boolean) to authenticated;
grant execute on function public.add_bazar_item(uuid,text,numeric,text,numeric) to authenticated;
grant execute on function public.delete_bazar_item(uuid) to authenticated;
grant execute on function public.recalculate_bazar_entry_total(uuid) to authenticated;
grant execute on function public.create_bazar_entry_with_items(uuid,date,text,text,jsonb) to authenticated;
grant execute on function public.create_expense(uuid,uuid,numeric,date,text,text) to authenticated;
grant execute on function public.update_expense(uuid,uuid,numeric,date,text,text) to authenticated;
grant execute on function public.void_expense(uuid,text) to authenticated;
grant execute on function public.create_deposit(uuid,uuid,numeric,date,text,text) to authenticated;
grant execute on function public.void_deposit(uuid,text) to authenticated;
grant execute on function public.ensure_my_meals(uuid,date,integer) to authenticated;
grant execute on function public.set_my_meal(uuid,uuid,date,public.meal_status) to authenticated;
grant execute on function public.finalize_due_meals(uuid) to authenticated;
grant execute on function public.manager_set_meal(uuid,public.meal_status,text) to authenticated;
grant execute on function public.save_meal_cutoff(uuid,uuid,time,boolean) to authenticated;
