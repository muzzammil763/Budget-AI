-- Retires end-to-end encryption and gives the public tables clearer names.
--
-- Finance entries now sync as plain rows in public.finance_entries. The old
-- ciphertext tables are kept, renamed with a legacy_ prefix, only so each
-- client can decrypt its existing rows locally on next launch, copy them
-- into finance_entries, and delete the legacy rows. The server never had
-- the key, so this conversion cannot happen in SQL. A later migration drops
-- the legacy tables once every account has been converted.

-- 1. Renames. Policies, triggers, grants, foreign keys, and realtime
-- publication membership follow the table, not its name.
alter table public.user_settings rename to users;
alter table public.app_user_roles rename to user_roles;
alter table public.ai_user_limits rename to user_ai_limits;
alter table public.ai_usage_monthly rename to ai_usage;
alter table public.ai_request_log rename to ai_requests;
alter table public.encrypted_finance_entries
  rename to legacy_encrypted_finance_entries;
alter table public.user_encryption rename to legacy_user_encryption;

-- 2. Function bodies reference tables by name, so rewrite every function
-- that mentions an old name. Reading the live definitions keeps whichever
-- version of each quota/admin function is currently deployed.
do $$
declare
  fn record;
  definition text;
begin
  for fn in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prokind = 'f'
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e'
      )
  loop
    definition := pg_get_functiondef(fn.oid);
    if definition ~ 'public\.(user_settings|app_user_roles|ai_user_limits|ai_usage_monthly|ai_request_log|encrypted_finance_entries|user_encryption)\M' then
      definition := regexp_replace(
        definition, 'public\.user_settings\M', 'public.users', 'g');
      definition := regexp_replace(
        definition, 'public\.app_user_roles\M', 'public.user_roles', 'g');
      definition := regexp_replace(
        definition, 'public\.ai_user_limits\M', 'public.user_ai_limits', 'g');
      definition := regexp_replace(
        definition, 'public\.ai_usage_monthly\M', 'public.ai_usage', 'g');
      definition := regexp_replace(
        definition, 'public\.ai_request_log\M', 'public.ai_requests', 'g');
      definition := regexp_replace(
        definition,
        'public\.encrypted_finance_entries\M',
        'public.legacy_encrypted_finance_entries',
        'g');
      definition := regexp_replace(
        definition,
        'public\.user_encryption\M',
        'public.legacy_user_encryption',
        'g');
      execute definition;
    end if;
  end loop;
end;
$$;

-- 3. Legacy tables become read-and-delete only: clients read their old
-- ciphertext once, then remove it after copying it into finance_entries.
alter publication supabase_realtime
  drop table public.legacy_encrypted_finance_entries;

revoke insert, update on table public.legacy_encrypted_finance_entries
  from authenticated;
revoke insert, update on table public.legacy_user_encryption
  from authenticated;
grant select, delete on table public.legacy_user_encryption to authenticated;

drop policy if exists "Users can insert their encrypted finances"
  on public.legacy_encrypted_finance_entries;
drop policy if exists "Users can update their encrypted finances"
  on public.legacy_encrypted_finance_entries;
drop policy if exists "Users can insert their encryption metadata"
  on public.legacy_user_encryption;
drop policy if exists "Users can update their encryption metadata"
  on public.legacy_user_encryption;

create policy "Users can delete their encryption metadata"
  on public.legacy_user_encryption for delete to authenticated
  using ((select auth.uid()) = user_id);

-- 4. Plain finance entries, one column per FinanceEntry field. `date` and
-- `created_at` are wall-clock timestamps without a zone, matching how the
-- app records entry times.
create table public.finance_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (char_length(id) between 1 and 128),
  type text not null default 'expense'
    check (type in ('expense', 'income')),
  amount double precision not null default 0,
  category text not null default 'Other',
  description text not null default '',
  date timestamp not null,
  has_time boolean not null default false,
  created_at timestamp not null,
  revision bigint not null default 1 check (revision > 0),
  is_deleted boolean not null default false,
  client_updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  device_id uuid not null,
  operation_id uuid not null,
  primary key (user_id, id),
  unique (user_id, operation_id)
);

create index finance_entries_pull_idx
  on public.finance_entries (user_id, server_updated_at, id);

create trigger finance_entries_server_updated_at
before update on public.finance_entries
for each row execute function private.set_server_updated_at();

alter table public.finance_entries enable row level security;

create policy "Users can read their finance entries"
  on public.finance_entries for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can insert their finance entries"
  on public.finance_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their finance entries"
  on public.finance_entries for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their finance entries"
  on public.finance_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.finance_entries from public, anon;
grant select, insert, update, delete on table public.finance_entries
  to authenticated;
grant all on table public.finance_entries to service_role;

alter publication supabase_realtime add table public.finance_entries;
