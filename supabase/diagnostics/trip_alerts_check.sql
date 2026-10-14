-- Read-only health check for driver trip alerts.
-- Paste into Supabase → SQL Editor → Run. Changes nothing.
create or replace function pg_temp.trip_alert_check()
returns table (step text, result text) language plpgsql as $$
begin
  return query select '1. pg_net installed (database can call functions)',
    coalesce((select extversion from pg_extension where extname = 'pg_net'), 'NO');
  return query select '2. alert trigger on trips',
    coalesce((select 'yes' from pg_trigger where tgname = 'trips_notify_admins'), 'NO');
  return query select '3. phones registered for alerts',
    coalesce((select string_agg(p.full_name || ' (' || p.role || ', ' || d.platform || ')', ', ')
              from public.device_tokens d join public.profiles p on p.id = d.user_id), 'NONE');
  return query select '4. alerts recorded by the function',
    coalesce((select string_agg(trip_id || ' ' || event, ', ')
              from (select * from public.trip_alerts order by sent_at desc limit 5) a), 'NONE');
  return query select '5. latest trips',
    (select string_agg(id || ' ' || status, ', ')
       from (select id, status from public.trips order by id desc limit 3) t);
  if to_regclass('net._http_response') is not null then
    return query execute $q$
      select '6. last calls from database to function',
             coalesce(string_agg(coalesce(status_code::text, 'ERR') || ' ' ||
               left(coalesce(content::text, error_msg, ''), 150), '  |  '), 'NONE')
        from (select * from net._http_response order by created desc limit 3) r $q$;
  end if;
end $$;

select * from pg_temp.trip_alert_check();
