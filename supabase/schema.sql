-- =====================================================================
--  Trip Logbook – Supabase backend
--  Run this whole file once in: Supabase Dashboard > SQL Editor > New query
-- =====================================================================

-- ---------- PROFILES (one row per login user) ------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  role        text not null default 'driver' check (role in ('driver', 'admin')),
  created_at  timestamptz not null default now()
);

-- Auto-create a profile whenever a user is added in Authentication
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Users created before this file was run get a profile too
insert into public.profiles (id, full_name)
select id, coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1))
from auth.users
on conflict (id) do nothing;

-- Helper: is the current user an admin?
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- VEHICLES -------------------------------------------------
create table if not exists public.vehicles (
  id             bigint generated always as identity primary key,
  reg_no         text not null unique,          -- e.g. LEB-1234
  description    text,                          -- e.g. Toyota Hilux (white)
  last_odometer  integer not null default 0,    -- auto-updated when a trip ends
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- ---------- TRIPS ----------------------------------------------------
create table if not exists public.trips (
  id             bigint generated always as identity primary key,
  driver_id      uuid not null default auth.uid() references public.profiles(id),
  vehicle_id     bigint not null references public.vehicles(id),
  status         text not null default 'ongoing' check (status in ('ongoing', 'completed')),

  start_time     timestamptz not null default now(),
  start_mileage  integer not null check (start_mileage >= 0),
  purpose        text not null,
  destination    text not null,

  end_time       timestamptz,
  end_mileage    integer,
  distance_km    integer generated always as (end_mileage - start_mileage) stored,
  fuel_litres    numeric(7,2)  check (fuel_litres >= 0),
  fuel_cost      numeric(10,2) check (fuel_cost >= 0),
  notes          text,

  created_at     timestamptz not null default now(),

  constraint end_not_below_start check (end_mileage is null or end_mileage >= start_mileage),
  constraint completed_needs_end check (status = 'ongoing' or (end_mileage is not null and end_time is not null))
);

-- A driver can only have one open trip, and a vehicle can only be on one open trip
create unique index if not exists one_open_trip_per_driver  on public.trips (driver_id)  where status = 'ongoing';
create unique index if not exists one_open_trip_per_vehicle on public.trips (vehicle_id) where status = 'ongoing';
create index if not exists trips_start_time_idx on public.trips (start_time desc);

-- GPS stamp taken by the phone when the trip starts / ends (null if unavailable)
alter table public.trips add column if not exists start_lat      double precision;
alter table public.trips add column if not exists start_lng      double precision;
alter table public.trips add column if not exists start_accuracy real;  -- metres
alter table public.trips add column if not exists end_lat        double precision;
alter table public.trips add column if not exists end_lng        double precision;
alter table public.trips add column if not exists end_accuracy   real;  -- metres

-- Secret per trip that lets the driver's phone upload route points from a
-- background service without the driver's login (see add_trip_points).
alter table public.trips add column if not exists tracking_key text not null
  default replace(gen_random_uuid()::text, '-', '');

-- Set when a finished trip is corrected afterwards (shown as "Edited" in the app)
alter table public.trips add column if not exists edited_at timestamptz;

alter table public.trips drop constraint if exists end_not_before_start;
alter table public.trips add constraint end_not_before_start
  check (end_time is null or end_time >= start_time);

-- Server controls timestamps & ownership (drivers can't back-date trips)
create or replace function public.trips_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not public.is_admin() then
      new.driver_id  := auth.uid();
      new.start_time := now();
      new.created_at := now();
    end if;
    if not exists (select 1 from public.vehicles where id = new.vehicle_id and active) then
      raise exception 'This vehicle is inactive. Ask your admin.';
    end if;
    new.status := 'ongoing';
    new.end_time := null; new.end_mileage := null;
    new.end_lat := null; new.end_lng := null; new.end_accuracy := null;
  else -- UPDATE
    new.tracking_key := old.tracking_key; -- fixed for the life of the trip
    if not public.is_admin() then
      new.driver_id  := old.driver_id;
      new.start_time := old.start_time;
      new.vehicle_id := old.vehicle_id;
      new.created_at := old.created_at;
      new.start_lat := old.start_lat; new.start_lng := old.start_lng;
      new.start_accuracy := old.start_accuracy;
      if old.status = 'completed' then
        -- Correcting a finished trip (allowed for 24 h, see trips_update policy):
        -- it stays finished, and its end time and end GPS can't be changed.
        new.status   := 'completed';
        new.end_time := old.end_time;
        new.end_lat := old.end_lat; new.end_lng := old.end_lng;
        new.end_accuracy := old.end_accuracy;
      elsif new.status = 'completed' then
        new.end_time := now(); -- end time is always the server clock for drivers
      else
        new.end_time := null;
      end if;
    elsif new.status = 'completed' and old.status = 'ongoing' and new.end_time is null then
      new.end_time := now();
    end if;
    if old.status = 'completed' then
      new.edited_at := now();
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trips_guard on public.trips;
create trigger trips_guard before insert or update on public.trips
  for each row execute function public.trips_guard();

-- Keep each vehicle's last_odometer right when trips end, are corrected or deleted
create or replace function public.trips_update_odometer()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  fallback integer; -- reading to use if the changed trip was the latest one
begin
  -- A finished trip was deleted, or its end reading corrected: if it was the
  -- vehicle's latest reading, fall back to the best remaining reading.
  if tg_op = 'DELETE' then
    if old.status = 'completed' then
      fallback := old.start_mileage;
    end if;
  elsif tg_op = 'UPDATE' then
    if old.status = 'completed' and new.end_mileage is distinct from old.end_mileage then
      fallback := new.end_mileage;
    end if;
  end if;

  if fallback is not null then
    update public.vehicles v
       set last_odometer = greatest(fallback, coalesce(
             (select max(t.end_mileage) from public.trips t
               where t.vehicle_id = old.vehicle_id and t.status = 'completed'
                 and t.id <> old.id), 0))
     where v.id = old.vehicle_id and v.last_odometer = old.end_mileage;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.status = 'completed' and new.end_mileage is not null then
    update public.vehicles
       set last_odometer = greatest(last_odometer, new.end_mileage)
     where id = new.vehicle_id;
  end if;
  return new;
end $$;

drop trigger if exists trips_update_odometer on public.trips;
create trigger trips_update_odometer after insert or update or delete on public.trips
  for each row execute function public.trips_update_odometer();

-- ---------- ROW LEVEL SECURITY --------------------------------------
alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.trips    enable row level security;

-- Profiles: see yourself; admin sees & edits everyone
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Vehicles: everyone logged in can read; only admin can change
drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles for select to authenticated using (true);
drop policy if exists vehicles_admin_all on public.vehicles;
create policy vehicles_admin_all on public.vehicles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Trips: drivers see/create their own; they can edit while the trip is open
-- and for 24 hours after it ends. Only admins can delete.
drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips for insert to authenticated
  with check (driver_id = auth.uid() or public.is_admin());

drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips for update to authenticated
  using ((driver_id = auth.uid()
          and (status = 'ongoing' or end_time > now() - interval '24 hours'))
         or public.is_admin())
  with check (driver_id = auth.uid() or public.is_admin());

drop policy if exists trips_admin_delete on public.trips;
create policy trips_admin_delete on public.trips for delete to authenticated
  using (public.is_admin());

-- ---------- TRIP ALERTS FOR ADMINS (push notifications) ----------------
-- Each admin phone registers its Firebase token here; when a trip starts or
-- ends, a trigger calls the trip-alerts Edge Function, which sends the push.

create table if not exists public.device_tokens (
  token       text primary key,                 -- Firebase Cloud Messaging token
  user_id     uuid not null references public.profiles(id) on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens for select to authenticated
  using (user_id = auth.uid());

-- A token belongs to whoever is signed in on that phone right now
-- (handles a shared phone switching between accounts).
create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void language sql security definer set search_path = public as $$
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
$$;

create or replace function public.unregister_device_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

-- Each alert is sent once per trip and event (the Edge Function records it here).
create table if not exists public.trip_alerts (
  trip_id  bigint not null references public.trips(id) on delete cascade,
  event    text not null check (event in ('start', 'end')),
  sent_at  timestamptz not null default now(),
  primary key (trip_id, event)
);
alter table public.trip_alerts enable row level security; -- no policies: server only

-- pg_net lets the database call the Edge Function (enabled by default on Supabase).
do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net not available – trip alerts disabled';
end $$;

create or replace function public.trips_notify_admins()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ev text;
begin
  if tg_op = 'INSERT' then
    ev := 'start';
  elsif old.status = 'ongoing' and new.status = 'completed' then
    ev := 'end';
  else
    return new;
  end if;

  perform net.http_post(
    url     := 'https://ofvpqdqnvmgdnyyjgevi.supabase.co/functions/v1/trip-alerts',
    body    := jsonb_build_object('trip_id', new.id, 'event', ev),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  return new;
exception when others then
  return new; -- an alert problem must never stop a trip being saved
end $$;

drop trigger if exists trips_notify_admins on public.trips;
create trigger trips_notify_admins after insert or update on public.trips
  for each row execute function public.trips_notify_admins();

-- ---------- LIVE LOCATION / ROUTES ------------------------------------
-- While a trip is open the driver's phone records a GPS point about once a
-- minute. Admins see the live position and the route; drivers their own.

create table if not exists public.trip_points (
  id           bigint generated always as identity primary key,
  trip_id      bigint not null references public.trips(id) on delete cascade,
  driver_id    uuid not null default auth.uid() references public.profiles(id),
  recorded_at  timestamptz not null,           -- when the phone took the fix
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  accuracy     real,                           -- metres
  speed        real,                           -- metres / second
  created_at   timestamptz not null default now()
);
create index if not exists trip_points_trip_time_idx
  on public.trip_points (trip_id, recorded_at desc);

alter table public.trip_points enable row level security;

drop policy if exists trip_points_select on public.trip_points;
create policy trip_points_select on public.trip_points for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

-- Drivers add points only to their own trip while it is open – plus 30 min
-- after ending, so points saved up without signal can still be uploaded.
drop policy if exists trip_points_insert on public.trip_points;
create policy trip_points_insert on public.trip_points for insert to authenticated
  with check (
    driver_id = auth.uid()
    and exists (
      select 1 from public.trips t
       where t.id = trip_id and t.driver_id = auth.uid()
         and (t.status = 'ongoing' or t.end_time > now() - interval '30 minutes')
    )
  );
-- No update/delete policies: route points can't be altered (admins delete
-- the whole trip, which removes its points).

-- Upload route points with the trip's tracking key. Works without a login so
-- the background tracking service keeps going if the app is swiped away.
-- Only for that trip, only while it's open (or ended < 30 min ago).
create or replace function public.add_trip_points(p_trip_id bigint, p_key text, p_points jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  t record;
  n integer;
begin
  select id, driver_id, status, end_time, tracking_key into t
    from public.trips where id = p_trip_id;
  if t.id is null or t.tracking_key is distinct from p_key then
    raise exception 'Unknown trip or wrong tracking key' using errcode = '42501';
  end if;
  if not (t.status = 'ongoing' or t.end_time > now() - interval '30 minutes') then
    raise exception 'Trip is closed' using errcode = '42501';
  end if;
  if jsonb_typeof(p_points) <> 'array' or jsonb_array_length(p_points) > 500 then
    raise exception 'Send between 1 and 500 points' using errcode = '22023';
  end if;

  insert into public.trip_points (trip_id, driver_id, recorded_at, lat, lng, accuracy, speed)
  select p_trip_id, t.driver_id,
         (e->>'recorded_at')::timestamptz, (e->>'lat')::float8, (e->>'lng')::float8,
         (e->>'accuracy')::real, (e->>'speed')::real
    from jsonb_array_elements(p_points) e
   where (e->>'recorded_at')::timestamptz <= now() + interval '5 minutes';
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.add_trip_points(bigint, text, jsonb) from public;
grant execute on function public.add_trip_points(bigint, text, jsonb) to anon, authenticated;

-- Live map: the app is told the moment a route point is saved (Supabase
-- Realtime). Access rules above still apply to who receives what.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime'
                        and schemaname = 'public' and tablename = 'trip_points') then
    alter publication supabase_realtime add table public.trip_points;
  end if;
end $$;

-- Detailed route points older than 3 months are deleted every night
-- (03:15 PKT); the trips themselves are kept forever.
create or replace function public.purge_old_trip_points()
returns integer language sql security definer set search_path = public as $$
  with gone as (
    delete from public.trip_points
     where recorded_at < now() - interval '3 months'
    returning 1
  )
  select count(*)::integer from gone;
$$;
revoke all on function public.purge_old_trip_points() from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('purge-old-trip-points', '15 22 * * *',
                        'select public.purge_old_trip_points()');
exception when others then
  raise notice 'pg_cron unavailable (%): run  select public.purge_old_trip_points();  by hand now and then', sqlerrm;
end $$;

-- Latest known position of each trip (Fleet status map).
create or replace view public.trip_last_point with (security_invoker = on) as
  select distinct on (trip_id) trip_id, lat, lng, accuracy, speed, recorded_at
    from public.trip_points
   order by trip_id, recorded_at desc;

-- =====================================================================
--  AFTER running this file:
--  1) Authentication > Users > Add user  (create yourself + each driver)
--  2) Make yourself admin (change the email):
--       update public.profiles set role = 'admin'
--       where id = (select id from auth.users where email = 'you@weatherwalay.com');
--  3) Set driver names:  Table Editor > profiles > full_name
--  4) Add vehicles from the app (Admin > Vehicles) or Table Editor > vehicles
--
--  This file is safe to run again (e.g. after an app update) – it only adds
--  what is missing and replaces functions/policies.
-- =====================================================================
