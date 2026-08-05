-- Temporary plaintext counterpart to encrypted_finance_entries. See
-- ENCRYPTION_REVERT_PLAN.md at the repo root for why this exists and how to
-- revert to the encrypted-only path. encrypted_finance_entries and
-- user_encryption are left untouched by this migration.
create table public.plain_finance_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_id text not null check (char_length(entry_id) between 1 and 128),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  revision bigint not null default 1 check (revision > 0),
  is_deleted boolean not null default false,
  client_updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  device_id uuid not null,
  operation_id uuid not null,
  primary key (user_id, entry_id),
  unique (user_id, operation_id)
);

create index plain_finance_entries_pull_idx
  on public.plain_finance_entries (user_id, server_updated_at, entry_id);

create trigger plain_finance_entries_server_updated_at
before update on public.plain_finance_entries
for each row execute function private.set_server_updated_at();

alter table public.plain_finance_entries enable row level security;

create policy "Users can read their plain finances"
  on public.plain_finance_entries for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can insert their plain finances"
  on public.plain_finance_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their plain finances"
  on public.plain_finance_entries for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their plain finances"
  on public.plain_finance_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.plain_finance_entries from public, anon;

grant select, insert, update, delete
  on table public.plain_finance_entries to authenticated;

grant all on table public.plain_finance_entries to service_role;

alter publication supabase_realtime add table public.plain_finance_entries;
