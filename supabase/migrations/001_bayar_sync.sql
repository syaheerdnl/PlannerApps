-- Bayar sync tables.
--
-- Run this once in your own Supabase project (SQL editor). It creates one table
-- per local table, turns on row-level security so every user can only see and
-- change THEIR OWN rows, and stamps every save with the server's clock.
--
-- Notes:
--  * The primary key is (user_id, id), not just id. The default envelopes (Fuel,
--    Food, Other) have the same fixed id on every phone, so two different users
--    would otherwise collide.
--  * Dates such as due_date are plain text 'YYYY-MM-DD', exactly as on the phone.
--  * There are no foreign keys here on purpose: rows can arrive in any order, and
--    the app already enforces the links locally.

-- clock_timestamp(), not now(): now() is frozen at the START of the transaction, so a row would
-- be stamped earlier than the moment it becomes visible. clock_timestamp() is the actual time of
-- the save, which keeps the stamp as close to the commit as it can be. (The app also re-reads the
-- last 30 seconds on every pull, to cover the small gap between a stamp and its commit.)
create or replace function public.bayar_touch() returns trigger
language plpgsql as $$
begin
  new.server_updated_at = clock_timestamp();
  return new;
end;
$$;

-- ── obligations (bills) ─────────────────────────────────────────────────────
create table if not exists public.obligations (
  user_id            uuid not null default auth.uid() references auth.users on delete cascade,
  id                 uuid not null,
  name               text not null,
  amount_sen         integer not null check (amount_sen >= 0),
  is_estimate        integer not null default 0,
  frequency          text not null,
  interval_count     integer not null default 1 check (interval_count >= 1),
  start_date         text not null,
  end_date           text,
  pay_by_buffer_days integer not null default 0 check (pay_by_buffer_days >= 0),
  note               text,
  created_at         timestamptz not null,
  updated_at         timestamptz not null,
  deleted_at         timestamptz,
  server_updated_at  timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── payments ────────────────────────────────────────────────────────────────
create table if not exists public.payments (
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  id                uuid not null,
  obligation_id     uuid not null,
  due_date          text not null,
  amount_sen        integer not null check (amount_sen >= 0),
  paid_at           timestamptz not null,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── envelopes ───────────────────────────────────────────────────────────────
create table if not exists public.envelopes (
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  id                uuid not null,
  name              text not null,
  sort_order        integer not null default 0,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── allocations (the budget per envelope per pay cycle) ─────────────────────
create table if not exists public.allocations (
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  id                uuid not null,
  envelope_id       uuid not null,
  cycle_start       text not null,
  amount_sen        integer not null check (amount_sen >= 0),
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── spendings ───────────────────────────────────────────────────────────────
create table if not exists public.spendings (
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  id                uuid not null,
  envelope_id       uuid not null,
  amount_sen        integer not null check (amount_sen > 0),
  note              text,
  spent_on          text not null,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── settings (payday, salary) ───────────────────────────────────────────────
create table if not exists public.settings (
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  key               text not null,
  value             text not null,
  updated_at        timestamptz not null,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- ── server clock stamp, indexes, and row-level security on every table ──────
do $$
declare t text;
begin
  foreach t in array array['obligations','payments','envelopes','allocations','spendings','settings']
  loop
    execute format('drop trigger if exists bayar_touch on public.%I', t);
    execute format(
      'create trigger bayar_touch before insert or update on public.%I
         for each row execute function public.bayar_touch()', t);

    execute format(
      'create index if not exists %I on public.%I (user_id, server_updated_at)',
      t || '_sync_idx', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format(
      'create policy "own rows" on public.%I
         for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;
