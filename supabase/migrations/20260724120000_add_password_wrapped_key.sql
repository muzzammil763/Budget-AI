-- Adds a password-wrapped copy of each account's data key alongside the
-- existing recovery-key mechanism. The data key itself never changes here:
-- it is still the same AES-256 key generated at first-time encryption
-- setup, and it still decrypts encrypted_finance_entries the same way.
-- This migration only adds a second, parallel envelope around that key —
-- one derived from the account password (Argon2id) instead of typed in
-- manually — so a normal email/password login can unlock a new device
-- without the user having to copy a recovery key across devices. The
-- recovery key remains the fallback for the one case password-derivation
-- cannot cover: a password reset via email link, which invalidates the
-- old password before a new device can ever use it to unwrap anything.
alter table public.user_encryption
  add column password_salt text
    check (password_salt is null or char_length(password_salt) between 16 and 64),
  add column wrapped_key_ciphertext text
    check (
      wrapped_key_ciphertext is null or char_length(wrapped_key_ciphertext) > 0
    ),
  add column wrapped_key_nonce text
    check (
      wrapped_key_nonce is null
      or char_length(wrapped_key_nonce) between 12 and 64
    ),
  add column wrapped_key_mac text
    check (
      wrapped_key_mac is null or char_length(wrapped_key_mac) between 16 and 128
    ),
  add constraint user_encryption_password_wrap_complete check (
    (
      password_salt is null
      and wrapped_key_ciphertext is null
      and wrapped_key_nonce is null
      and wrapped_key_mac is null
    )
    or (
      password_salt is not null
      and wrapped_key_ciphertext is not null
      and wrapped_key_nonce is not null
      and wrapped_key_mac is not null
    )
  );
