-- MessMate Bazar Items Schema Compatibility
-- Initial schema uses `amount`; item RPCs use `unit_price`.
-- Keep the existing column for backward compatibility and add the richer unit-price field.

alter table public.bazar_items
  add column if not exists unit_price numeric(12,2);

update public.bazar_items
set unit_price = coalesce(unit_price, amount)
where unit_price is null;

alter table public.bazar_items
  alter column unit_price set default 0;

update public.bazar_items bi
set amount = round((coalesce(bi.quantity, 0) * coalesce(bi.unit_price, 0))::numeric, 2)
where bi.quantity is not null;

-- Keep legacy amount synchronized with quantity × unit_price.
create or replace function public.sync_bazar_item_amount()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.amount := round((coalesce(new.quantity, 0) * coalesce(new.unit_price, 0))::numeric, 2);
  return new;
end;
$$;

drop trigger if exists trg_sync_bazar_item_amount on public.bazar_items;
create trigger trg_sync_bazar_item_amount
before insert or update of quantity, unit_price on public.bazar_items
for each row execute function public.sync_bazar_item_amount();

-- Recreate the item-total trigger after the compatibility column exists.
create or replace function public.sync_bazar_entry_total_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry_id uuid;
begin
  v_entry_id := coalesce(new.bazar_entry_id, old.bazar_entry_id);

  update public.bazar_entries be
  set total_amount = (
    select coalesce(sum(round(coalesce(bi.quantity, 0) * coalesce(bi.unit_price, 0), 2)), 0)::numeric(12,2)
    from public.bazar_items bi
    where bi.bazar_entry_id = v_entry_id
  ),
  updated_at = now()
  where be.id = v_entry_id
    and be.status <> 'approved';

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_sync_bazar_entry_total on public.bazar_items;
create trigger trg_sync_bazar_entry_total
after insert or update or delete on public.bazar_items
for each row execute function public.sync_bazar_entry_total_trigger();
