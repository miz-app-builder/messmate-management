-- Schedule meal reminders/locks without requiring the manager to open the app.
-- Supabase projects may need pg_cron enabled from Database > Extensions first.
create extension if not exists pg_cron with schema extensions;

create or replace function public.run_messmate_meal_notifications()
returns integer
language plpgsql security definer set search_path=public
as $$
declare r record; v_total integer:=0;
begin
 for r in select id from public.messes loop
   begin v_total:=v_total+coalesce(public.notify_meal_events(r.id,(timezone('Asia/Dhaka',now()))::date),0); exception when others then null; end;
 end loop;
 return v_total;
end;
$$;

grant execute on function public.run_messmate_meal_notifications() to service_role;
revoke all on function public.run_messmate_meal_notifications() from public,authenticated;

-- Every 15 minutes: lock due meals and issue due reminders/lock notifications.
select cron.schedule('messmate-meal-events','*/15 * * * *',$$select public.run_messmate_meal_notifications();$$)
where not exists (select 1 from cron.job where jobname='messmate-meal-events');

-- Daily at 20:00 Asia/Dhaka: prepare/send tomorrow reminder. The function itself is idempotent.
select cron.schedule('messmate-tomorrow-meal-reminder','0 14 * * *',$$select public.run_messmate_meal_notifications();$$)
where not exists (select 1 from cron.job where jobname='messmate-tomorrow-meal-reminder');
