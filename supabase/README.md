# Setting up sync (optional)

Bayar works fully offline. Sync only adds "the same data on every phone".

1. Create a free project at https://supabase.com (you do this yourself, in your own account).
2. Open **SQL editor**, paste `migrations/001_bayar_sync.sql`, and run it.
3. In **Project settings → API**, copy the **Project URL** and the **anon public key**.
4. Build the app with them:

   ```bash
   flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
               --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
   ```

5. In the app open **Plan → Sync across devices**, create an account, then sign in with the
   same account on your other phone.

The anon key is meant to be public. Your data is protected by the row-level security rules in
the SQL file: each signed-in user can only read and write their own rows. Never put the
`service_role` key in the app.

Note: if "Confirm email" is on in your project (Authentication settings), new accounts must click
the link in their email before they can sign in.

## Testing the SQL without a Supabase project

`tests/sync_sql_test.js` runs `migrations/001_bayar_sync.sql` in a real Postgres (PGlite, Postgres compiled to
WebAssembly) and checks row-level security, the constraints, the server timestamp and the pull. It imitates
Supabase's `auth.uid()` and the `authenticated` role, so it is a close check, not a replacement for trying a
real project.

```bash
mkdir /tmp/pgtest && cd /tmp/pgtest && npm init -y && npm install @electric-sql/pglite
node /path/to/bayar/supabase/tests/sync_sql_test.js /path/to/bayar/supabase/migrations/001_bayar_sync.sql
```
