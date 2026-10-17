# Private notes: Supabase Google login with Row Level Security

A small React + Vite app where each user signs in with Google and can only read and edit their own rows in a `notes` table. Access control is enforced in the database with Row Level Security (RLS), not in the frontend.

## What is in the repo

| Path                                                           | Purpose                                                          |
| -------------------------------------------------------------- | ---------------------------------------------------------------- |
| `supabase/migrations/20261017000000_create_notes_with_rls.sql` | Creates the `notes` table, enables RLS, and defines the policies |
| `supabase/tests/rls_test.sql`                                  | Automated two-user test, run in the SQL editor                   |
| `src/`                                                         | React app (Google login, list, add, edit, delete)                |
| `.env.example`                                                 | Names of the environment variables, no real values               |

## How RLS is set up

- `notes.user_id` defaults to `auth.uid()`, so the client never sends it and cannot spoof it.
- RLS is enabled and forced on the table.
- Four policies (select, insert, update, delete) allow access only where `auth.uid() = user_id`.
- The update policy has both `USING` and `WITH CHECK`, so a user cannot reassign a row to someone else.
- The `anon` role has all privileges revoked, so signed-out requests get nothing.

## Setup

1. Create a project at supabase.com.
2. **Google login.** In Google Cloud Console, create an OAuth client (type: Web application). Add this authorized redirect URI: `https://<your-project-ref>.supabase.co/auth/v1/callback`. In Supabase, go to Authentication > Providers > Google, enable it, and paste the client ID and secret there. The Google secret lives only in the Supabase dashboard, never in this repo.
3. **Redirect URLs.** In Authentication > URL Configuration, set Site URL to `http://localhost:5173` and add the same URL to Redirect URLs.
4. **Run the migration.** Paste `supabase/migrations/20261017000000_create_notes_with_rls.sql` into the SQL editor and run it (or use `supabase db push` with the Supabase CLI).
5. **Environment.**
   ```bash
   cp .env.example .env
   # fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY from Project Settings > API
   ```
   Only the anon key is used. The `service_role` key is never used in this app or committed.
6. **Run.**
   ```bash
   npm install
   npm run dev
   ```
   Open http://localhost:5173.

## How I tested with two users

### Test 1: automated SQL test

Paste `supabase/tests/rls_test.sql` into the SQL editor and run it. It creates two fake users (A and B), impersonates each in turn using the same JWT claims mechanism the API uses, then rolls everything back.

It asserts that:

- A can read and edit their own note.
- B cannot read, update or delete A's note (0 rows visible or affected).
- B cannot insert a row with A's `user_id` (rejected by RLS).
- B cannot reassign their own note to A.
- A signed-out (`anon`) caller cannot query the table.

A successful run ends with `All RLS checks passed`.

### Test 2: manual test through the app with two Google accounts

1. Sign in as **User A** (Google account 1) and add a note titled "Test 1, RLS notes". In the browser console, get its id:
   ```js
   const { data } = await supabase.from("notes").select("id");
   console.log(data[0].id);
   ```
   (`window.supabase` is exposed in dev mode only.)
2. Sign out, then sign in as **User B** (Google account 2).
3. Confirm the list shows only User B’s own notes, not User A’s.
4. With A's note `id` (`AID`), try to access it as B from the console. Nothing is returned or changed:
   ```js
   await supabase.from("notes").select().eq("id", AID); // data: []
   await supabase
     .from("notes")
     .update({ body: "hacked" })
     .eq("id", AID)
     .select(); // data: []
   await supabase.from("notes").delete().eq("id", AID).select(); // data: []
   await supabase
     .from("notes")
     .insert({ user_id: "<A's user id>", title: "forged" });
   // error: new row violates row-level security policy for table "notes"
   ```
5. In the Supabase Table Editor (admin view), confirm A's note is unchanged.

## Results

- SQL test (`rls_test.sql`): `All RLS checks passed`.
- Signed in as User B, the notes list shows only User B's notes.
- As User B, reading, updating and deleting User A's note by id returned `data: []` and changed nothing.
- As User B, inserting a note with User A's `user_id` failed with HTTP 403 (row-level security violation).
- User A's note was unchanged in the Table Editor afterward.

## Security notes

- No secrets in the frontend or the repo. `.env` is gitignored and only `.env.example` is committed.
- The anon key is public by design. It is safe only because RLS is enabled on every table in the exposed schema.
- If more tables are added later, enable RLS and add policies in the same migration.
