-- The Plaid experiment is not part of the active application. Its tables are
-- empty, and the temporary plaintext finance table has been superseded by the
-- verified encrypted sync path.
drop table if exists public.bank_accounts;
drop table if exists public.bank_sync_history;
drop table if exists public.bank_connections;
drop table if exists public.plain_finance_entries;

-- This trigger helper was introduced exclusively for the Plaid tables.
drop function if exists private.set_updated_at();
