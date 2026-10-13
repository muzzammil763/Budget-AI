-- Every account has been converted from the retired end-to-end encryption
-- to plain finance_entries, so the ciphertext tables are no longer read.
-- The `backup` schema was a manual pre-conversion copy and is removed too.
drop table if exists public.legacy_encrypted_finance_entries;
drop table if exists public.legacy_user_encryption;
drop schema if exists backup cascade;
