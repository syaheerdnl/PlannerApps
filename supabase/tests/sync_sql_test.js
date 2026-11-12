// Runs supabase/migrations/001_bayar_sync.sql in a REAL Postgres (PGlite) and checks what the
// app relies on. Supabase's own pieces (auth.users, auth.uid(), the "authenticated" role, and
// PostgREST's upsert) are imitated just enough to run the file.
const fs = require('fs');
const { PGlite } = require('@electric-sql/pglite');

const SQL = process.argv[2];
const A = '11111111-1111-1111-1111-111111111111';
const B = '22222222-2222-2222-2222-222222222222';
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  ok   ' + m); } else { fail++; console.log('  FAIL ' + m); } };

async function expectError(db, sql, params, re, m) {
  try { await db.query(sql, params); ok(false, m + ' (no error)'); }
  catch (e) { ok(re.test(e.message), m + '  [' + e.message.slice(0, 70) + ']'); }
}

// Act as a signed-in Supabase user: role authenticated + the JWT claim auth.uid() reads.
async function as(db, uid) {
  await db.exec(`reset role; set role authenticated; select set_config('request.jwt.claim.sub','${uid}',false);`);
}
async function asAdmin(db) { await db.exec('reset role;'); }

(async () => {
  const db = new PGlite();

  // ---- imitate Supabase's environment -------------------------------------------------
  await db.exec(`
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create role authenticated nologin;
    create role anon nologin;
    grant usage on schema public, auth to authenticated, anon;
    alter default privileges in schema public grant all on tables to authenticated;
    insert into auth.users values ('${A}'), ('${B}');
  `);

  console.log('1. the migration runs, and can be run again');
  const sql = fs.readFileSync(SQL, 'utf8');
  try { await db.exec(sql); ok(true, 'first run'); } catch (e) { ok(false, 'first run: ' + e.message); process.exit(1); }
  try { await db.exec(sql); ok(true, 'second run (idempotent)'); } catch (e) { ok(false, 'second run: ' + e.message); }
  await db.exec('grant all on all tables in schema public to authenticated;');

  const tables = (await db.query(`select tablename, rowsecurity from pg_tables where schemaname='public' order by 1`)).rows;
  ok(tables.length === 6, '6 tables created: ' + tables.map(t => t.tablename).join(', '));
  ok(tables.every(t => t.rowsecurity), 'row-level security is ON for every table');
  const trg = (await db.query(`select count(*)::int n from pg_trigger where tgname='bayar_touch'`)).rows[0].n;
  ok(trg === 6, 'a bayar_touch trigger on each table (and not doubled by the 2nd run)');

  // the exact upsert PostgREST builds for supabase_flutter: ON CONFLICT (user_id,id) DO UPDATE
  const upsertObl = (uid, id, name, amount, upd) => db.query(
    `insert into public.obligations (user_id,id,name,amount_sen,frequency,start_date,created_at,updated_at)
     values ($1,$2,$3,$4,'monthly','2026-11-12',now(),$5)
     on conflict (user_id,id) do update set name=excluded.name, amount_sen=excluded.amount_sen,
       updated_at=excluded.updated_at`, [uid, id, name, amount, upd]);
  const ID1 = 'aaaaaaaa-0000-0000-0000-000000000001';

  console.log('2. a signed-in user can save, and only sees their own rows');
  await as(db, A);
  await upsertObl(A, ID1, 'Car loan', 52000, '2026-11-12T00:00:00Z');
  ok((await db.query('select * from public.obligations')).rows.length === 1, 'A sees their own bill');
  await as(db, B);
  ok((await db.query('select * from public.obligations')).rows.length === 0, 'B cannot see A\'s bill');
  await expectError(db, `insert into public.obligations (user_id,id,name,amount_sen,frequency,start_date,created_at,updated_at)
     values ($1,'aaaaaaaa-0000-0000-0000-000000000002','Sneaky',1,'monthly','2026-11-12',now(),now())`, [A],
     /row-level security/i, 'B cannot write a row AS A');
  const upd = await db.query(`update public.obligations set name='hacked' where id=$1`, [ID1]);
  ok(upd.affectedRows === 0, 'B cannot update A\'s row (0 rows affected)');
  const del = await db.query(`delete from public.obligations where id=$1`, [ID1]);
  ok(del.affectedRows === 0, 'B cannot delete A\'s row');
  await asAdmin(db);
  ok((await db.query(`select name from public.obligations where user_id=$1`, [A])).rows[0].name === 'Car loan', 'A\'s row is untouched');

  console.log('3. two users can use the SAME id (default envelopes share fixed ids)');
  await as(db, B);
  await upsertObl(B, ID1, 'B\'s own bill', 100, '2026-11-12T00:00:00Z');
  ok((await db.query('select name from public.obligations')).rows[0].name === 'B\'s own bill', 'B saves the same id without clashing');
  await asAdmin(db);
  ok((await db.query('select count(*)::int n from public.obligations')).rows[0].n === 2, 'both rows exist side by side');

  console.log('4. user_id defaults to the signed-in user');
  await as(db, A);
  await db.query(`insert into public.envelopes (id,name,created_at,updated_at) values ('eeeeeeee-0000-0000-0000-000000000001','Fuel',now(),now())`);
  ok((await db.query('select user_id from public.envelopes')).rows[0].user_id === A, 'user_id = auth.uid() when the app omits it');

  console.log('5. server_updated_at is stamped by the server');
  await as(db, A);
  await upsertObl(A, ID1, 'Car loan', 52000, '2026-11-12T00:00:00Z');
  const t1 = (await db.query(`select server_updated_at t from public.obligations`)).rows[0].t;
  await new Promise(r => setTimeout(r, 20));
  await upsertObl(A, ID1, 'Car loan v2', 53000, '2026-11-12T00:00:01Z');
  const t2 = (await db.query(`select server_updated_at t from public.obligations`)).rows[0].t;
  ok(t2 > t1, 'an update moves server_updated_at forward');
  // a client cannot forge it
  await db.query(`insert into public.settings (key,value,updated_at,server_updated_at) values ('forge','1',now(),'2000-01-01')`);
  const forged = (await db.query(`select server_updated_at t from public.settings where key='forge'`)).rows[0].t;
  ok(forged > new Date('2020-01-01'), 'a client-supplied server_updated_at is overwritten');

  console.log('6. stamps are the time of the save, not the start of the transaction');
  await as(db, A);
  await db.exec('begin');
  const t0 = (await db.query('select now() t')).rows[0].t;
  await new Promise(r => setTimeout(r, 30));
  await db.query(`insert into public.obligations (id,name,amount_sen,frequency,start_date,created_at,updated_at)
     values ('cccccccc-0000-0000-0000-000000000001','Late in tx',1,'monthly','2026-11-12',now(),now())`);
  const stamp = (await db.query(`select server_updated_at t from public.obligations where name='Late in tx'`)).rows[0].t;
  await db.exec('commit');
  ok(stamp > t0, 'a row saved 30ms into a transaction is stamped AFTER the transaction started (clock_timestamp, not now())');

  console.log("7. the app's real pull: one filtered query, ordered by (stamp, key), paged by offset");
  await as(db, A);
  const values = Array.from({ length: 251 }, (_, i) =>
    `('${A}','bbbbbbbb-0000-0000-0000-${String(i).padStart(12, '0')}','Bill ${i}',100,'monthly','2026-11-12',now(),now())`).join(',');
  await db.query(`insert into public.obligations (user_id,id,name,amount_sen,frequency,start_date,created_at,updated_at) values ${values}`);
  const total = (await db.query('select count(*)::int n from public.obligations')).rows[0].n;
  const seen = new Set(); let pages = 0;
  for (let off = 0; ; off += 60) {
    const r = await db.query(`select id from public.obligations order by server_updated_at asc, id asc limit 60 offset $1`, [off]);
    r.rows.forEach(x => seen.add(x.id)); pages++;
    if (r.rows.length < 60) break;
  }
  ok(seen.size === total, `pulled ${seen.size} of ${total} rows over ${pages} pages, none lost or doubled`);
  // incremental pull: "stamp > cursor" returns only newer rows
  const cursor = (await db.query('select max(server_updated_at) t from public.obligations')).rows[0].t;
  await new Promise(r => setTimeout(r, 5));
  await upsertObl(A, 'dddddddd-0000-0000-0000-0000000000aa', 'Newer', 1, '2026-11-12T00:00:00Z');
  const newer = (await db.query('select name from public.obligations where server_updated_at > $1', [cursor])).rows;
  ok(newer.length === 1 && newer[0].name === 'Newer', 'a pull after the cursor returns just the new row');
  // timestamps come back in the format the app parses
  const raw = (await db.query(`select to_char(server_updated_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"') s from public.obligations limit 1`)).rows[0].s;
  ok(!isNaN(Date.parse(raw)), 'server_updated_at is a parseable timestamp with microseconds: ' + raw);

  console.log('8. constraints');
  await as(db, A);
  const ins = (extra) => `insert into public.spendings (id,envelope_id,amount_sen,spent_on,created_at,updated_at) values ('${extra}','eeeeeeee-0000-0000-0000-000000000001',`;
  await expectError(db, ins('dddddddd-0000-0000-0000-000000000001') + `0,'2026-11-12',now(),now())`, [], /check/i, 'a spending of 0 sen is rejected');
  await expectError(db, ins('dddddddd-0000-0000-0000-000000000002') + `-5,'2026-11-12',now(),now())`, [], /check/i, 'a negative spending is rejected');
  await expectError(db, `insert into public.obligations (id,name,amount_sen,frequency,start_date,interval_count,created_at,updated_at)
    values ('dddddddd-0000-0000-0000-000000000003','x',1,'monthly','2026-11-12',0,now(),now())`, [], /check/i, 'interval_count 0 is rejected');
  await expectError(db, `insert into public.obligations (id,name,frequency,start_date,created_at,updated_at)
    values ('dddddddd-0000-0000-0000-000000000004','x','monthly','2026-11-12',now(),now())`, [], /null value/i, 'a missing amount is rejected');
  await db.query(`insert into public.settings (key,value,updated_at) values ('payday','25',now())`);
  await db.query(`insert into public.settings (key,value,updated_at) values ('payday','26',now()) on conflict (user_id,key) do update set value=excluded.value`);
  ok((await db.query(`select value from public.settings where key='payday'`)).rows[0].value === '26', 'settings upsert on (user_id,key) overwrites');

  console.log('9. the app\'s timestamps and null deleted_at round-trip');
  await as(db, A);
  await db.query(`update public.obligations set deleted_at='2026-11-12T10:00:00+00:00' where id=$1`, [ID1]);
  ok((await db.query(`select deleted_at from public.obligations where id=$1`, [ID1])).rows[0].deleted_at !== null, 'soft delete stored (rows are never removed, so other phones learn of deletes)');

  console.log('10. deleting a user removes their data');
  await asAdmin(db);
  await db.query(`delete from auth.users where id=$1`, [B]);
  ok((await db.query(`select count(*)::int n from public.obligations where user_id=$1`, [B])).rows[0].n === 0, 'B\'s rows cascade away');
  ok((await db.query(`select count(*)::int n from public.obligations where user_id=$1`, [A])).rows[0].n > 0, 'A\'s rows remain');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('CRASH', e); process.exit(2); });
