-- MessMate Bazar Item Total Sync
create or replace function public.recalculate_bazar_entry_total(p_bazar_entry_id uuid)
returns numeric language plpgsql security definer set search_path=public as $$
declare v_entry public.bazar_entries%rowtype; v_total numeric(14,2);
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into v_entry from public.bazar_entries where id=p_bazar_entry_id;
 if not found then raise exception 'Bazar entry not found'; end if;
 if v_entry.status='approved' then raise exception 'Approved bazar entries cannot be changed'; end if;
 if not public.has_mess_permission(v_entry.mess_id,'can_add_bazar') then raise exception 'Bazar entry permission is required'; end if;
 if not exists(select 1 from public.mess_members mm where mm.id=v_entry.buyer_member_id and mm.user_id=auth.uid() and mm.status='active') and not public.is_mess_manager(v_entry.mess_id) then raise exception 'You can only edit your own bazar entries'; end if;
 select coalesce(sum(quantity*unit_price),0)::numeric(14,2) into v_total from public.bazar_items where bazar_entry_id=p_bazar_entry_id;
 update public.bazar_entries set total_amount=v_total,updated_at=now() where id=p_bazar_entry_id;
 insert into public.audit_logs(mess_id,actor_user_id,action,entity_type,entity_id,old_data,new_data) values(v_entry.mess_id,auth.uid(),'update','bazar_entry',p_bazar_entry_id,jsonb_build_object('total_amount',v_entry.total_amount),jsonb_build_object('total_amount',v_total,'source','bazar_items'));
 return v_total;
end; $$;
grant execute on function public.recalculate_bazar_entry_total(uuid) to authenticated;
revoke all on function public.recalculate_bazar_entry_total(uuid) from public;

create or replace function public.sync_bazar_entry_total_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_entry_id uuid;
begin
 v_entry_id=coalesce(new.bazar_entry_id,old.bazar_entry_id);
 update public.bazar_entries be set total_amount=(select coalesce(sum(bi.quantity*bi.unit_price),0)::numeric(14,2) from public.bazar_items bi where bi.bazar_entry_id=v_entry_id),updated_at=now() where be.id=v_entry_id and be.status<>'approved';
 return coalesce(new,old);
end; $$;
drop trigger if exists trg_sync_bazar_entry_total on public.bazar_items;
create trigger trg_sync_bazar_entry_total after insert or update or delete on public.bazar_items for each row execute function public.sync_bazar_entry_total_trigger();
