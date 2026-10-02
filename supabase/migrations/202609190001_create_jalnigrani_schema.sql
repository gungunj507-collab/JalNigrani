-- JalNigrani public schema. Run this in the Supabase SQL Editor.
create extension if not exists pgcrypto;

do $$ begin
  create type public.profile_role as enum ('user', 'admin');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.device_status as enum ('online', 'offline', 'maintenance', 'disabled');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.reading_status as enum ('normal', 'warning', 'critical');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.alert_priority as enum ('low', 'medium', 'high', 'critical');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.alert_status as enum ('active', 'acknowledged', 'resolved');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text, phone text, timezone text not null default 'Asia/Kolkata',
  role public.profile_role not null default 'user',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.water_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null, device_identifier text not null unique, zone text, location text,
  status public.device_status not null default 'offline', installed_at timestamptz, last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint water_devices_name_not_blank check (length(btrim(name)) > 0)
);

create table if not exists public.water_readings (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.water_devices(id) on delete cascade,
  recorded_at timestamptz not null default now(), availability numeric(5,2), flow_rate numeric(12,3),
  usage_litres numeric(14,3) not null default 0, usage_percent numeric(5,2),
  status public.reading_status not null default 'normal', sensor_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint water_readings_availability_range check (availability is null or availability between 0 and 100),
  constraint water_readings_flow_rate_nonnegative check (flow_rate is null or flow_rate >= 0),
  constraint water_readings_usage_nonnegative check (usage_litres >= 0),
  constraint water_readings_usage_percent_range check (usage_percent is null or usage_percent between 0 and 100),
  constraint water_readings_device_recorded_at_key unique (device_id, recorded_at)
);

create table if not exists public.alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.water_devices(id) on delete set null,
  type text not null, message text not null, priority public.alert_priority not null default 'medium',
  status public.alert_status not null default 'active', detected_at timestamptz not null default now(),
  acknowledged_at timestamptz, resolved_at timestamptz, resolved_by uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint alerts_type_not_blank check (length(btrim(type)) > 0),
  constraint alerts_message_not_blank check (length(btrim(message)) > 0),
  constraint alerts_resolution_consistent check ((status <> 'resolved') or (resolved_at is not null and resolved_by is not null))
);

create index if not exists water_devices_user_id_idx on public.water_devices (user_id);
create index if not exists water_readings_device_recorded_at_idx on public.water_readings (device_id, recorded_at desc);
create index if not exists alerts_user_detected_at_idx on public.alerts (user_id, detected_at desc);
create index if not exists alerts_device_detected_at_idx on public.alerts (device_id, detected_at desc);
create index if not exists alerts_active_idx on public.alerts (user_id, detected_at desc) where status <> 'resolved';

create function public.set_updated_at() returns trigger language plpgsql security invoker set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name) values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '')) on conflict (id) do nothing;
  return new;
end;
$$;

create function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create function public.owns_device(target_device_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.water_devices where id = target_device_id and user_id = auth.uid());
$$;

create function public.validate_alert_device_owner() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.device_id is not null and not exists (select 1 from public.water_devices where id = new.device_id and user_id = new.user_id) then
    raise exception 'alert device must belong to alert user';
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute procedure public.set_updated_at();
drop trigger if exists water_devices_set_updated_at on public.water_devices;
create trigger water_devices_set_updated_at before update on public.water_devices for each row execute procedure public.set_updated_at();
drop trigger if exists alerts_set_updated_at on public.alerts;
create trigger alerts_set_updated_at before update on public.alerts for each row execute procedure public.set_updated_at();
drop trigger if exists alerts_validate_device_owner on public.alerts;
create trigger alerts_validate_device_owner before insert or update on public.alerts for each row execute procedure public.validate_alert_device_owner();

-- Backfill users created before this migration.
insert into public.profiles (id, full_name)
select id, nullif(btrim(raw_user_meta_data ->> 'full_name'), '') from auth.users on conflict (id) do nothing;

alter table public.profiles enable row level security;
alter table public.water_devices enable row level security;
alter table public.water_readings enable row level security;
alter table public.alerts enable row level security;

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "devices_select_own_or_admin" on public.water_devices;
drop policy if exists "devices_insert_own_or_admin" on public.water_devices;
drop policy if exists "devices_update_own_or_admin" on public.water_devices;
drop policy if exists "devices_delete_own_or_admin" on public.water_devices;
drop policy if exists "readings_select_owner_or_admin" on public.water_readings;
drop policy if exists "alerts_select_own_or_admin" on public.alerts;
drop policy if exists "alerts_update_own_or_admin" on public.alerts;
create policy "profiles_select_own_or_admin" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "devices_select_own_or_admin" on public.water_devices for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "devices_insert_own_or_admin" on public.water_devices for insert to authenticated with check (user_id = auth.uid() or public.is_admin());
create policy "devices_update_own_or_admin" on public.water_devices for update to authenticated using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
create policy "devices_delete_own_or_admin" on public.water_devices for delete to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "readings_select_owner_or_admin" on public.water_readings for select to authenticated using (public.owns_device(device_id) or public.is_admin());
create policy "alerts_select_own_or_admin" on public.alerts for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "alerts_update_own_or_admin" on public.alerts for update to authenticated using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());

-- Browser: read data and resolve alerts only. Sensor ingestion must use a server/Edge Function with a server-only service-role key.
revoke all on public.profiles, public.water_devices, public.water_readings, public.alerts from anon;
grant select on public.profiles, public.water_devices, public.water_readings, public.alerts to authenticated;
grant insert, update, delete on public.water_devices to authenticated;
grant update (full_name, phone, timezone) on public.profiles to authenticated;
revoke insert, update, delete on public.water_readings from authenticated;
revoke insert, delete on public.alerts from authenticated;
grant update (status, acknowledged_at, resolved_at, resolved_by) on public.alerts to authenticated;
revoke execute on function public.set_updated_at(), public.handle_new_user(), public.validate_alert_device_owner() from public;
revoke execute on function public.is_admin(), public.owns_device(uuid) from public;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.owns_device(uuid) to authenticated;

-- Verification (run after applying this migration as the project owner).
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('profiles', 'water_devices', 'water_readings', 'alerts')
order by table_name;

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'water_devices', 'water_readings', 'alerts')
order by table_name, ordinal_position;
