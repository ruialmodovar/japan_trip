-- Execute uma vez no SQL Editor para substituir a antiga lista fixa.
-- A partir daqui, uma sessão válida do Supabase é a única condição de acesso.

create or replace function public.is_japan_trip_member()
returns boolean language sql stable security definer set search_path = ''
as $$ select (select auth.uid()) is not null; $$;

revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

drop policy if exists "trip participants can view shared locations" on public.trip_locations;
create policy "trip participants can view shared locations"
on public.trip_locations for select to authenticated
using ((select auth.uid()) is not null and updated_at > now() - interval '6 hours');

drop policy if exists "participants can insert own location" on public.trip_locations;
create policy "participants can insert own location"
on public.trip_locations for insert to authenticated
with check (
  user_id = (select auth.uid())
  and email = (select auth.jwt() ->> 'email')
);

drop policy if exists "trip members share expenses" on public.trip_expenses;
create policy "trip members share expenses" on public.trip_expenses
for all to authenticated
using ((select auth.uid()) is not null)
with check (
  owner_user_id = (select auth.uid())
  and owner_email = (select auth.jwt() ->> 'email')
);
