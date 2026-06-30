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

drop policy if exists "trip participants can view shared locations" on public.trip_locations;
create policy "trip participants can view shared locations"
on public.trip_locations for select
to authenticated
using (
  (select auth.jwt() ->> 'email') = any (array[
    'ruialmodovar@gmail.com',
    'ana.botinas@gmail.com',
    'raquelbotinascoelho@gmail.com',
    'mateus80@gmail.com',
    'luestrellado@gmail.com',
    'biaestrellado@gmail.com'
  ])
  and updated_at > now() - interval '6 hours'
);

drop policy if exists "participants can insert own location" on public.trip_locations;
create policy "participants can insert own location"
on public.trip_locations for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and email = (select auth.jwt() ->> 'email')
  and email = any (array[
    'ruialmodovar@gmail.com', 'ana.botinas@gmail.com',
    'raquelbotinascoelho@gmail.com', 'mateus80@gmail.com',
    'luestrellado@gmail.com', 'biaestrellado@gmail.com'
  ])
);

drop policy if exists "participants can update own location" on public.trip_locations;
create policy "participants can update own location"
on public.trip_locations for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id and email = (select auth.jwt() ->> 'email'));

drop policy if exists "participants can delete own location" on public.trip_locations;
create policy "participants can delete own location"
on public.trip_locations for delete
to authenticated
using ((select auth.uid()) = user_id);

create index if not exists trip_locations_updated_at_idx
on public.trip_locations (updated_at desc);
