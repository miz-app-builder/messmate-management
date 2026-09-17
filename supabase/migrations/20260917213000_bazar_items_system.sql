-- MessMate Bazar Items
-- Item-level bazar lines for each bazar entry.

create or replace function public.add_bazar_item(
  p_bazar_entry_id uuid,
  p_item_name text,
  p_quantity numeric,
  p_unit text,
  p_unit_price numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry public.bazar_entries%rowtype;
  v_item_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_item_name), '') is null then raise exception 'Item name is required'; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_unit_price < 0 then raise exception 'Unit price cannot be negative'; end if;

  select * into v_entry
  from public.bazar_entries
  where id = p_bazar_entry_id;

  if not found then raise exception 'Bazar entry not found'; end if;
  if v_entry.status = 'approved' then raise exception 'Approved bazar entries cannot be changed'; end if;

  if not public.has_mess_permission(v_entry.mess_id, 'can_add_bazar') then
    raise exception 'Bazar entry permission is required';
  end if;

  if not exists (
    select 1 from public.mess_members mm
    where mm.id = v_entry.buyer_member_id
      and mm.user_id = auth.uid()
      and mm.status = 'active'
  ) and not public.is_mess_manager(v_entry.mess_id) then
    raise exception 'You can only edit your own bazar entries';
  end if;

  insert into public.bazar_items(
    bazar_entry_id, item_name, quantity, unit, unit_price
  )
  values(
    p_bazar_entry_id, trim(p_item_name), p_quantity, nullif(trim(p_unit), ''), p_unit_price
  )
  returning id into v_item_id;

  insert into public.audit_logs(
    mess_id, actor_user_id, action, entity_type, entity_id, old_data, new_data
  )
  values(
    v_entry.mess_id, auth.uid(), 'create', 'bazar_item', v_item_id, null,
    jsonb_build_object(
      'bazar_entry_id', p_bazar_entry_id,
      'item_name', trim(p_item_name),
      'quantity', p_quantity,
      'unit', p_unit,
      'unit_price', p_unit_price
    )
  );

  return v_item_id;
end;
$$;

create or replace function public.delete_bazar_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.bazar_items%rowtype;
  v_entry public.bazar_entries%rowtype;
begin
  select * into v_item from public.bazar_items where id = p_item_id;
  if not found then raise exception 'Bazar item not found'; end if;

  select * into v_entry from public.bazar_entries where id = v_item.bazar_entry_id;
  if v_entry.status = 'approved' then raise exception 'Approved bazar entries cannot be changed'; end if;

  if not public.has_mess_permission(v_entry.mess_id, 'can_add_bazar') then
    raise exception 'Bazar entry permission is required';
  end if;

  if not exists (
    select 1 from public.mess_members mm
    where mm.id = v_entry.buyer_member_id
      and mm.user_id = auth.uid()
      and mm.status = 'active'
  ) and not public.is_mess_manager(v_entry.mess_id) then
    raise exception 'You can only edit your own bazar entries';
  end if;

  delete from public.bazar_items where id = p_item_id;

  insert into public.audit_logs(
    mess_id, actor_user_id, action, entity_type, entity_id, old_data, new_data
  )
  values(
    v_entry.mess_id, auth.uid(), 'delete', 'bazar_item', p_item_id,
    jsonb_build_object(
      'bazar_entry_id', v_item.bazar_entry_id,
      'item_name', v_item.item_name,
      'quantity', v_item.quantity,
      'unit', v_item.unit,
      'unit_price', v_item.unit_price
    ), null
  );
end;
$$;

grant execute on function public.add_bazar_item(uuid,text,numeric,text,numeric) to authenticated;
grant execute on function public.delete_bazar_item(uuid) to authenticated;

revoke all on function public.add_bazar_item(uuid,text,numeric,text,numeric) from public;
revoke all on function public.delete_bazar_item(uuid) from public;
