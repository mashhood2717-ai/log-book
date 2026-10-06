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
