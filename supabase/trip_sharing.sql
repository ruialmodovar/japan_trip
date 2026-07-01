-- Execute uma vez no Supabase SQL Editor.
-- Cria a partilha de despesas e fotografias apenas para os seis participantes.

create or replace function public.is_japan_trip_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.jwt() ->> 'email') = any (array[
    'ruialmodovar@gmail.com',
    'ana.botinas@gmail.com',
    'raquelbotinascoelho@gmail.com',
    'mateus80@gmail.com',
    'luestrellado@gmail.com',
    'biaestrellado@gmail.com'
  ]);
$$;

revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

create table if not exists public.trip_expenses (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  owner_email text not null,
  title text not null check (char_length(title) between 1 and 160),
  amount double precision not null check (amount > 0),
  currency text not null check (currency in ('BRL', 'AED', 'JPY', 'EUR', 'USD')),
  expense_date timestamptz not null,
  category text not null,
  payer_email text not null,
  participant_emails text[] not null check (cardinality(participant_emails) > 0),
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.trip_photos (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  owner_email text not null,
  storage_path text not null unique,
  caption text not null default '',
  created_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create or replace function public.set_japan_trip_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_trip_expenses_updated_at on public.trip_expenses;
create trigger set_trip_expenses_updated_at before update on public.trip_expenses
for each row execute function public.set_japan_trip_updated_at();

drop trigger if exists set_trip_photos_updated_at on public.trip_photos;
create trigger set_trip_photos_updated_at before update on public.trip_photos
for each row execute function public.set_japan_trip_updated_at();

alter table public.trip_expenses enable row level security;
alter table public.trip_photos enable row level security;
revoke all on public.trip_expenses, public.trip_photos from anon;
grant select, insert, update, delete on public.trip_expenses, public.trip_photos to authenticated;

drop policy if exists "trip members share expenses" on public.trip_expenses;
create policy "trip members share expenses" on public.trip_expenses
for all to authenticated
using ((select public.is_japan_trip_member()))
with check (
  (select public.is_japan_trip_member())
  and owner_email = any (array[
    'ruialmodovar@gmail.com', 'ana.botinas@gmail.com',
    'raquelbotinascoelho@gmail.com', 'mateus80@gmail.com',
    'luestrellado@gmail.com', 'biaestrellado@gmail.com'
  ])
);

drop policy if exists "trip members view photos" on public.trip_photos;
create policy "trip members view photos" on public.trip_photos
for select to authenticated using ((select public.is_japan_trip_member()));

drop policy if exists "trip members add own photos" on public.trip_photos;
create policy "trip members add own photos" on public.trip_photos
for insert to authenticated with check (
  (select public.is_japan_trip_member())
  and owner_user_id = (select auth.uid())
  and owner_email = (select auth.jwt() ->> 'email')
);

drop policy if exists "trip members update own photos" on public.trip_photos;
create policy "trip members update own photos" on public.trip_photos
for update to authenticated
using (owner_user_id = (select auth.uid()))
with check (owner_user_id = (select auth.uid()) and owner_email = (select auth.jwt() ->> 'email'));

drop policy if exists "trip members delete own photos" on public.trip_photos;
create policy "trip members delete own photos" on public.trip_photos
for delete to authenticated using (owner_user_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trip-photos', 'trip-photos', false, 15728640, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "trip members view photo objects" on storage.objects;
create policy "trip members view photo objects" on storage.objects
for select to authenticated
using (bucket_id = 'trip-photos' and (select public.is_japan_trip_member()));

drop policy if exists "trip members upload own photo objects" on storage.objects;
create policy "trip members upload own photo objects" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'trip-photos'
  and (select public.is_japan_trip_member())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "trip members update own photo objects" on storage.objects;
create policy "trip members update own photo objects" on storage.objects
for update to authenticated
using (bucket_id = 'trip-photos' and owner_id::text = (select auth.uid())::text)
with check (bucket_id = 'trip-photos' and owner_id::text = (select auth.uid())::text);

drop policy if exists "trip members delete own photo objects" on storage.objects;
create policy "trip members delete own photo objects" on storage.objects
for delete to authenticated
using (bucket_id = 'trip-photos' and owner_id::text = (select auth.uid())::text);

create index if not exists trip_expenses_date_idx on public.trip_expenses (expense_date desc);
create index if not exists trip_photos_created_at_idx on public.trip_photos (created_at desc);
