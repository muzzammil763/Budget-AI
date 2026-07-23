create schema if not exists private;

create table public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default ''
    check (char_length(display_name) <= 80),
  model_id text not null default 'gpt-5.6-luna'
    check (char_length(model_id) between 1 and 80),
  currency_display text not null default 'USD'
    check (char_length(currency_display) between 1 and 16),
  custom_currencies jsonb not null default '[]'::jsonb
    check (jsonb_typeof(custom_currencies) = 'array'),
  bubble_style text not null default 'classic'
    check (char_length(bubble_style) between 1 and 40),
  client_updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  device_id uuid not null
);

create table public.user_encryption (
  user_id uuid primary key references auth.users(id) on delete cascade,
  key_fingerprint text not null
    check (key_fingerprint ~ '^[A-Za-z0-9_-]{16,64}$'),
  encryption_version smallint not null default 1
    check (encryption_version = 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.encrypted_finance_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_id text not null check (char_length(entry_id) between 1 and 128),
  ciphertext text not null check (char_length(ciphertext) > 0),
  nonce text not null check (char_length(nonce) between 12 and 64),
  mac text not null check (char_length(mac) between 16 and 128),
  encryption_version smallint not null default 1
    check (encryption_version = 1),
  revision bigint not null default 1 check (revision > 0),
  is_deleted boolean not null default false,
  client_updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  device_id uuid not null,
  operation_id uuid not null,
  primary key (user_id, entry_id),
  unique (user_id, operation_id)
);

create index encrypted_finance_entries_pull_idx
  on public.encrypted_finance_entries (user_id, server_updated_at, entry_id);

create or replace function private.set_server_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.server_updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_server_updated_at() from public, anon,
  authenticated;

create trigger user_settings_server_updated_at
before update on public.user_settings
for each row execute function private.set_server_updated_at();

create trigger encrypted_finance_entries_server_updated_at
before update on public.encrypted_finance_entries
for each row execute function private.set_server_updated_at();

alter table public.user_settings enable row level security;
alter table public.user_encryption enable row level security;
alter table public.encrypted_finance_entries enable row level security;

create policy "Users can read their own settings"
  on public.user_settings for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can insert their own settings"
  on public.user_settings for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their own settings"
  on public.user_settings for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their own settings"
  on public.user_settings for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their encryption metadata"
  on public.user_encryption for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can insert their encryption metadata"
  on public.user_encryption for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their encryption metadata"
  on public.user_encryption for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read their encrypted finances"
  on public.encrypted_finance_entries for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can insert their encrypted finances"
  on public.encrypted_finance_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their encrypted finances"
  on public.encrypted_finance_entries for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their encrypted finances"
  on public.encrypted_finance_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.user_settings from public, anon;
revoke all on table public.user_encryption from public, anon;
revoke all on table public.encrypted_finance_entries from public, anon;

grant select, insert, update, delete on table public.user_settings
  to authenticated;
grant select, insert, update on table public.user_encryption
  to authenticated;
grant select, insert, update, delete
  on table public.encrypted_finance_entries to authenticated;

grant all on table public.user_settings to service_role;
grant all on table public.user_encryption to service_role;
grant all on table public.encrypted_finance_entries to service_role;

alter publication supabase_realtime add table public.user_settings;
alter publication supabase_realtime
  add table public.encrypted_finance_entries;
