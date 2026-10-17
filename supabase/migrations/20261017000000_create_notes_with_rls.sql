-- Private notes: every row belongs to one user, enforced by Row Level Security.

create table public.notes (
  id         uuid primary key default gen_random_uuid(),
  -- Defaults to the caller's id, so clients never need to send user_id.
  user_id    uuid not null default auth.uid()
             references auth.users (id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 200),
  body       text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index notes_user_id_idx on public.notes (user_id);

-- Keep updated_at fresh on every update.
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger notes_set_updated_at
  before update on public.notes
  for each row execute function public.set_updated_at();

-- Turn RLS on. With RLS on and no matching policy, access is denied.
alter table public.notes enable row level security;
alter table public.notes force row level security;

-- Least privilege: signed-out (anon) callers get nothing at all.
revoke all on public.notes from anon;
grant select, insert, update, delete on public.notes to authenticated;

-- (select auth.uid()) lets Postgres evaluate the id once per query, not per row.

create policy "notes_select_own"
  on public.notes for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "notes_insert_own"
  on public.notes for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

-- USING limits which rows can be targeted; WITH CHECK stops a user from
-- reassigning a row to someone else by changing user_id.
create policy "notes_update_own"
  on public.notes for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "notes_delete_own"
  on public.notes for delete
  to authenticated
  using ((select auth.uid()) = user_id);
