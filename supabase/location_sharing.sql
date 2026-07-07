-- Execute uma vez no Supabase SQL Editor.
create table if not exists public.trip_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy double precision,
  updated_at timestamptz not null default now()
);

create or replace function public.set_trip_location_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_trip_location_updated_at on public.trip_locations;
create trigger set_trip_location_updated_at
before update on public.trip_locations
for each row execute function public.set_trip_location_updated_at();

alter table public.trip_locations enable row level security;
revoke all on public.trip_locations from anon;
grant select, insert, update, delete on public.trip_locations to authenticated;

create or replace function public.upsert_trip_location(
  latitude_value double precision,
  longitude_value double precision,
  accuracy_value double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
begin
  if current_user_id is null or current_email = '' then
    raise exception 'authenticated Supabase session required' using errcode = '42501';
  end if;

  insert into public.trip_locations (
    user_id,
    email,
    latitude,
    longitude,
    accuracy,
    updated_at
  )
  values (
    current_user_id,
    current_email,
    latitude_value,
    longitude_value,
    case when accuracy_value is null then null else greatest(0, accuracy_value) end,
    now()
  )
  on conflict (user_id) do update set
    email = excluded.email,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy = excluded.accuracy,
    updated_at = now()
  where public.trip_locations.user_id = current_user_id;
end;
$$;

create or replace function public.remove_own_trip_location()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.trip_locations
  where user_id = (select auth.uid());
$$;

revoke all on function public.upsert_trip_location(double precision, double precision, double precision) from public, anon;
revoke all on function public.remove_own_trip_location() from public, anon;
grant execute on function public.upsert_trip_location(double precision, double precision, double precision) to authenticated;
grant execute on function public.remove_own_trip_location() to authenticated;

drop policy if exists "trip participants can view shared locations" on public.trip_locations;
create policy "trip participants can view shared locations"
on public.trip_locations for select
to authenticated
using (
  (select auth.uid()) is not null
  and updated_at > now() - interval '6 hours'
);

drop policy if exists "participants can insert own location" on public.trip_locations;
create policy "participants can insert own location"
on public.trip_locations for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and lower(email) = lower((select auth.jwt() ->> 'email'))
);

drop policy if exists "participants can update own location" on public.trip_locations;
create policy "participants can update own location"
on public.trip_locations for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id and lower(email) = lower((select auth.jwt() ->> 'email')));

drop policy if exists "participants can delete own location" on public.trip_locations;
create policy "participants can delete own location"
on public.trip_locations for delete
to authenticated
using ((select auth.uid()) = user_id);

create index if not exists trip_locations_updated_at_idx
on public.trip_locations (updated_at desc);
