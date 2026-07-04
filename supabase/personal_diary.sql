-- Execute uma vez no Supabase SQL Editor.
-- Diário estritamente pessoal: nem os outros participantes podem ler as entradas.

create or replace function public.is_japan_trip_member()
returns boolean language sql stable security definer set search_path = ''
as $$ select (select auth.uid()) is not null; $$;
revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

create table if not exists public.trip_personal_diary (
  day_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  note text not null default '',
  mood smallint not null default 5 check (mood between 1 and 5),
  highlight text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (day_id, user_id)
);

create or replace function public.set_personal_diary_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists set_personal_diary_updated_at on public.trip_personal_diary;
create trigger set_personal_diary_updated_at before update on public.trip_personal_diary
for each row execute function public.set_personal_diary_updated_at();

alter table public.trip_personal_diary enable row level security;
revoke all on public.trip_personal_diary from anon;
grant select, insert, update, delete on public.trip_personal_diary to authenticated;

drop policy if exists "users read own diary" on public.trip_personal_diary;
create policy "users read own diary" on public.trip_personal_diary for select to authenticated
using (user_id = (select auth.uid()) and email = (select auth.jwt() ->> 'email'));

drop policy if exists "users create own diary" on public.trip_personal_diary;
create policy "users create own diary" on public.trip_personal_diary for insert to authenticated
with check (
  (select public.is_japan_trip_member())
  and user_id = (select auth.uid())
  and email = (select auth.jwt() ->> 'email')
);

drop policy if exists "users update own diary" on public.trip_personal_diary;
create policy "users update own diary" on public.trip_personal_diary for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and email = (select auth.jwt() ->> 'email'));

drop policy if exists "users delete own diary" on public.trip_personal_diary;
create policy "users delete own diary" on public.trip_personal_diary for delete to authenticated
using (user_id = (select auth.uid()));

create index if not exists trip_personal_diary_user_day_idx
on public.trip_personal_diary (user_id, day_id);
