-- Execute uma vez no Supabase SQL Editor.
-- Checklist geral partilhada e checklist pessoal privada por utilizador.

create or replace function public.is_japan_trip_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select (select auth.uid()) is not null; $$;

revoke all on function public.is_japan_trip_member() from public, anon;
grant execute on function public.is_japan_trip_member() to authenticated;

create table if not exists public.trip_checklist_items (
  id text primary key,
  title text not null check (char_length(title) between 1 and 300),
  section text not null check (section in ('Fazer agora', 'Antes da viagem', 'Durante a viagem', 'Já reservado')),
  scope text not null check (scope in ('general', 'personal')),
  is_completed boolean not null default false,
  owner_user_id uuid references auth.users(id) on delete cascade,
  owner_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_scope_owner_check check (
    (scope = 'general' and owner_user_id is null and owner_email is null)
    or
    (scope = 'personal' and owner_user_id is not null and owner_email is not null)
  )
);

create or replace function public.set_trip_checklist_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_trip_checklist_updated_at on public.trip_checklist_items;
create trigger set_trip_checklist_updated_at
before update on public.trip_checklist_items
for each row execute function public.set_trip_checklist_updated_at();

alter table public.trip_checklist_items enable row level security;
revoke all on public.trip_checklist_items from anon;
grant select, insert, update, delete on public.trip_checklist_items to authenticated;

drop policy if exists "members view general and own personal checklist" on public.trip_checklist_items;
create policy "members view general and own personal checklist"
on public.trip_checklist_items for select
to authenticated
using (
  (select public.is_japan_trip_member())
  and (scope = 'general' or owner_user_id = (select auth.uid()))
);

drop policy if exists "members create general or own personal checklist" on public.trip_checklist_items;
create policy "members create general or own personal checklist"
on public.trip_checklist_items for insert
to authenticated
with check (
  (select public.is_japan_trip_member())
  and (
    (scope = 'general' and owner_user_id is null and owner_email is null)
    or
    (scope = 'personal'
      and owner_user_id = (select auth.uid())
      and owner_email = (select auth.jwt() ->> 'email'))
  )
);

drop policy if exists "members update general or own personal checklist" on public.trip_checklist_items;
create policy "members update general or own personal checklist"
on public.trip_checklist_items for update
to authenticated
using (
  (select public.is_japan_trip_member())
  and (scope = 'general' or owner_user_id = (select auth.uid()))
)
with check (
  (select public.is_japan_trip_member())
  and (
    (scope = 'general' and owner_user_id is null and owner_email is null)
    or
    (scope = 'personal'
      and owner_user_id = (select auth.uid())
      and owner_email = (select auth.jwt() ->> 'email'))
  )
);

drop policy if exists "members delete general or own personal checklist" on public.trip_checklist_items;
create policy "members delete general or own personal checklist"
on public.trip_checklist_items for delete
to authenticated
using (
  (select public.is_japan_trip_member())
  and (scope = 'general' or owner_user_id = (select auth.uid()))
);

create index if not exists trip_checklist_scope_idx
on public.trip_checklist_items (scope, created_at);

create index if not exists trip_checklist_owner_idx
on public.trip_checklist_items (owner_user_id)
where scope = 'personal';
