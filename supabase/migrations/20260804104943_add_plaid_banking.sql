create schema if not exists private;

create table public.bank_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'plaid' check (provider = 'plaid'),
  item_id text not null unique check (char_length(item_id) between 1 and 255),
  encrypted_access_token text not null,
  token_nonce text not null,
  institution_id text,
  institution_name text not null default 'Connected bank'
    check (char_length(institution_name) between 1 and 160),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  sync_cursor text,
  sync_required boolean not null default true,
  status text not null default 'healthy'
    check (status in ('healthy', 'syncing', 'attention', 'disconnected')),
  consent_expires_at timestamptz,
  import_start_date date,
  import_end_date date,
  initial_import_complete boolean not null default false,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, item_id)
);

create index bank_connections_user_idx
  on public.bank_connections (user_id, created_at desc);

create table public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.bank_connections(id)
    on delete cascade,
  provider_account_id text not null check (char_length(provider_account_id) between 1 and 255),
  name text not null default 'Bank account' check (char_length(name) <= 160),
  mask text check (char_length(mask) <= 8),
  account_type text not null default 'account' check (char_length(account_type) <= 80),
  account_subtype text check (char_length(account_subtype) <= 80),
  currency_code text check (currency_code ~ '^[A-Z]{3}$'),
  selected boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connection_id, provider_account_id)
);

create table public.bank_sync_history (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.bank_connections(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  institution_name text not null check (char_length(institution_name) <= 160),
  status text not null check (status in ('completed', 'failed')),
  added_count integer not null default 0 check (added_count >= 0),
  modified_count integer not null default 0 check (modified_count >= 0),
  removed_count integer not null default 0 check (removed_count >= 0),
  error_code text check (char_length(error_code) <= 120),
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create index bank_sync_history_user_idx
  on public.bank_sync_history (user_id, started_at desc);

alter table public.bank_connections enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.bank_sync_history enable row level security;

revoke all on table public.bank_connections from public, anon, authenticated;
revoke all on table public.bank_accounts from public, anon, authenticated;
revoke all on table public.bank_sync_history from public, anon, authenticated;

grant all on table public.bank_connections to service_role;
grant all on table public.bank_accounts to service_role;
grant all on table public.bank_sync_history to service_role;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon,
  authenticated;

create trigger bank_connections_updated_at
before update on public.bank_connections
for each row execute function private.set_updated_at();

create trigger bank_accounts_updated_at
before update on public.bank_accounts
for each row execute function private.set_updated_at();
