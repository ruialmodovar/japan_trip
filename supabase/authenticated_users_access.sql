-- Execute uma vez no SQL Editor para substituir a antiga lista fixa.
-- A partir daqui, uma sessão válida do Supabase é a única condição de acesso.

create or replace function public.is_japan_trip_member()
returns boolean language sql stable security definer set search_path = ''
as $$ select (select auth.uid()) is not null; $$;

revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

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
on public.trip_locations for select to authenticated
using ((select auth.uid()) is not null and updated_at > now() - interval '6 hours');

drop policy if exists "participants can insert own location" on public.trip_locations;
create policy "participants can insert own location"
on public.trip_locations for insert to authenticated
with check (
  user_id = (select auth.uid())
  and lower(email) = lower((select auth.jwt() ->> 'email'))
);

drop policy if exists "participants can update own location" on public.trip_locations;
create policy "participants can update own location"
on public.trip_locations for update to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and lower(email) = lower((select auth.jwt() ->> 'email'))
);

drop policy if exists "participants can delete own location" on public.trip_locations;
create policy "participants can delete own location"
on public.trip_locations for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trip members share expenses" on public.trip_expenses;
create policy "trip members share expenses" on public.trip_expenses
for all to authenticated
using ((select auth.uid()) is not null)
with check (
  owner_user_id = (select auth.uid())
  and owner_email = (select auth.jwt() ->> 'email')
);
