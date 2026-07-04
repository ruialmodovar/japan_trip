-- Execute uma vez no Supabase SQL Editor.
-- Uma avaliação de 1 a 5 estrelas por utilizador e atividade.

create or replace function public.is_japan_trip_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select (select auth.uid()) is not null; $$;

revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

create table if not exists public.trip_activity_ratings (
  activity_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (activity_id, user_id)
);

create or replace function public.set_activity_rating_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_activity_rating_updated_at on public.trip_activity_ratings;
create trigger set_activity_rating_updated_at
before update on public.trip_activity_ratings
for each row execute function public.set_activity_rating_updated_at();

alter table public.trip_activity_ratings enable row level security;
revoke all on public.trip_activity_ratings from anon;
grant select, insert, update on public.trip_activity_ratings to authenticated;

drop policy if exists "trip members view activity ratings" on public.trip_activity_ratings;
create policy "trip members view activity ratings"
on public.trip_activity_ratings for select
to authenticated
using ((select public.is_japan_trip_member()));

drop policy if exists "trip members create own activity ratings" on public.trip_activity_ratings;
create policy "trip members create own activity ratings"
on public.trip_activity_ratings for insert
to authenticated
with check (
  (select public.is_japan_trip_member())
  and user_id = (select auth.uid())
  and email = (select auth.jwt() ->> 'email')
);

drop policy if exists "trip members update own activity ratings" on public.trip_activity_ratings;
create policy "trip members update own activity ratings"
on public.trip_activity_ratings for update
to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and email = (select auth.jwt() ->> 'email')
);

create index if not exists trip_activity_ratings_activity_idx
on public.trip_activity_ratings (activity_id, stars desc);

create index if not exists trip_activity_ratings_updated_idx
on public.trip_activity_ratings (updated_at desc);
