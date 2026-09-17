-- MessMate Bazar Atomic Item Create
-- Creates a bazar entry together with its item lines in one transaction.
-- This also supports approval-required OFF without creating an already-approved empty entry.

create or replace function public.create_bazar_entry_with_items(
  p_mess_id uuid,
  p_purchased_on date,
  p_note text,
  p_receipt_url text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.mess_members%rowtype;
  v_approval_required boolean;
  v_entry_id uuid;
  v_total numeric(14,2);
  v_item jsonb;
  v_name text;
  v_qty numeric;
  v_unit text;
  v_price numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into v_member
  from public.mess_members
  where mess_id = p_mess_id
    and user_id = auth.uid()
    and status = 'active'
  limit 1;

  if not found then raise exception 'Active mess membership is required'; end if;
  if not public.has_mess_permission(p_mess_id, 'can_add_bazar') then
    raise exception 'Bazar entry permission is required';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Items must be a JSON array';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'At least one bazar item is required';
  end if;

  select bazar_approval_required into v_approval_required
  from public.mess_settings
  where mess_id = p_mess_id;
  v_approval_required := coalesce(v_approval_required, true);

  select coalesce(sum(
    coalesce((x->>'quantity')::numeric, 0) * coalesce((x->>'unit_price')::numeric, 0)
  ), 0)::numeric(14,2)
  into v_total
  from jsonb_array_elements(p_items) x;

  if v_total < 0 then raise exception 'Total amount cannot be negative'; end if;

  insert into public.bazar_entries(
    mess_id, buyer_member_id, purchased_on, total_amount, status, note, receipt_url
  )
  values(
    p_mess_id, v_member.id, coalesce(p_purchased_on, current_date), v_total,
    case when v_approval_required then 'pending'::public.bazar_status else 'approved'::public.bazar_status end,
    nullif(trim(p_note), ''), nullif(trim(p_receipt_url), '')
  )
  returning id into v_entry_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_name := nullif(trim(v_item->>'item_name'), '');
    v_qty := (v_item->>'quantity')::numeric;
    v_unit := nullif(trim(v_item->>'unit'), '');
    v_price := (v_item->>'unit_price')::numeric;

    if v_name is null then raise exception 'Item name is required'; end if;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    if v_price is null or v_price < 0 then raise exception 'Unit price cannot be negative'; end if;

    insert into public.bazar_items(bazar_entry_id, item_name, quantity, unit, unit_price)
    values(v_entry_id, v_name, v_qty, v_unit, v_price);
  end loop;

  insert into public.audit_logs(
    mess_id, actor_user_id, action, entity_type, entity_id, old_data, new_data
  )
  values(
    p_mess_id, auth.uid(), 'create', 'bazar_entry', v_entry_id, null,
    jsonb_build_object(
      'total_amount', v_total,
      'status', case when v_approval_required then 'pending' else 'approved' end,
      'items', p_items
    )
  );

  return v_entry_id;
end;
$$;

grant execute on function public.create_bazar_entry_with_items(uuid,date,text,text,jsonb) to authenticated;
revoke all on function public.create_bazar_entry_with_items(uuid,date,text,text,jsonb) from public;
