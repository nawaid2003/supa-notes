-- Two-user RLS test. Run in the Supabase SQL editor (or psql) AFTER the migration.
-- Everything runs inside one transaction and is rolled back, so it leaves no data.
-- Any failed assertion aborts the script with a clear message.

begin;

-- Seed two fake users and one note owned by user A (runs as the admin role).
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user-a@example.test'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'user-b@example.test');

insert into public.notes (user_id, title, body) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'A private note', 'secret of A');

-- Act as a signed-in user (same mechanism PostgREST uses for the JWT).
set local role authenticated;

-- ===== User A =====
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

do $$
declare n int;
begin
  select count(*) into n from public.notes;
  assert n = 1, 'A should see exactly their own note';

  update public.notes set body = 'edited by A';
  get diagnostics n = row_count;
  assert n = 1, 'A should be able to edit their own note';
end $$;

-- ===== User B =====
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

do $$
declare n int;
begin
  -- B cannot read A's data.
  select count(*) into n from public.notes
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  assert n = 0, 'B must NOT read A''s rows';

  -- B cannot change A's data (the row is invisible, so 0 rows are touched).
  update public.notes set body = 'hacked by B'
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics n = row_count;
  assert n = 0, 'B must NOT update A''s rows';

  -- B cannot delete A's data.
  delete from public.notes
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics n = row_count;
  assert n = 0, 'B must NOT delete A''s rows';

  -- B cannot insert a row on behalf of A.
  begin
    insert into public.notes (user_id, title)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'forged by B');
    raise exception 'B inserted a row as A';
  exception when insufficient_privilege then
    null; -- expected: RLS WITH CHECK rejected it
  end;

  -- B can create and own their own note...
  insert into public.notes (title, body) values ('B note', 'mine');
  select count(*) into n from public.notes;
  assert n = 1, 'B should see only their own note';

  -- ...but cannot hand it over to A by changing user_id.
  begin
    update public.notes set user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    raise exception 'B reassigned a row to A';
  exception when insufficient_privilege then
    null; -- expected: RLS WITH CHECK rejected it
  end;
end $$;

-- ===== Signed-out (anon) =====
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
begin
  begin
    perform 1 from public.notes;
    raise exception 'anon was able to query notes';
  exception when insufficient_privilege then
    null; -- expected: no grants for anon
  end;
end $$;

reset role;
select 'All RLS checks passed' as result;

rollback;
