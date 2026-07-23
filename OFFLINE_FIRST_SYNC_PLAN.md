# Budget AI Offline-First Sync and Encryption Plan

## Product guarantees

- The app reads from and writes to its local SQLite database first.
- The interface remains usable without a network connection.
- Sync runs in the background after local writes and whenever connectivity or
  authentication returns.
- Chat conversations and message history remain local-only and are never
  uploaded to Supabase.
- Downloaded speech-model files remain local-only. Their selected model IDs may
  be remembered locally, but another device must download its own model files.
- Finance plaintext, descriptions, categories, and amounts must never be stored
  in Supabase.
- End-to-end encryption is opt-in and only activates after the user is shown
  the recovery key.

## Local SQLite database

Use SQLite databases for durable user data outside the existing local-only chat
database.

### `local_settings`

- `key text primary key`
- `value_json text not null`
- `sync_scope text not null` (`local` or `account`)
- `updated_at integer not null` (UTC microseconds)
- `sync_state text not null` (`clean`, `pending`, or `failed`)

Account-scoped settings:

- Display name
- OpenAI model
- Currency display
- Message bubble style

Local-only settings:

- Onboarding completion
- Selected offline STT and TTS model IDs
- Installed speech-model state derived from files on disk

### `finance_entries`

- `id text primary key`
- `payload_json text not null`
- `updated_at integer not null`
- `deleted_at integer`
- `sync_state text not null`
- `encryption_version integer`

Soft-deletion tombstones are retained locally until the server acknowledges
them. This prevents a deletion made offline from being recreated by an older
remote record.

### `sync_metadata`

- Per-table server cursor
- Last successful pull and push times
- Current user ID owning account-scoped rows
- Retry count and next retry time

## Supabase data model

### Profile and account settings

Profile names are stored in Supabase Auth user metadata and copied into the
local store on sign-in. The `user_settings` table synchronizes profile and
account preferences through Realtime. It:

- Reference `auth.users(id)` with `on delete cascade`.
- Enable RLS.
- Restrict every operation with `(select auth.uid()) = user_id`.
- Index `user_id` and any `(user_id, updated_at)` pull cursor.
- Use atomic upserts.

These settings are not authorization claims. User-controlled profile metadata
must never grant roles or elevated access.

### Encrypted finance records

The remote table stores only synchronization metadata and authenticated
ciphertext:

- `user_id uuid`
- `entry_id text`
- `ciphertext text`
- `nonce text`
- `encryption_version integer`
- `updated_at timestamptz`
- `deleted_at timestamptz`
- Primary key `(user_id, entry_id)`

RLS still isolates users even though the payload is encrypted. Supabase
Realtime is used as an invalidation signal; SQLite remains the source read by
the UI.

## End-to-end encryption

Supabase authentication passwords are not available to the app after sign-in
and must not be reused as encryption keys. Cross-device decryption therefore
requires a separate user-controlled recovery secret.

Recommended design:

1. Generate a random 256-bit account data key on the device.
2. Encrypt finance payloads with an audited AEAD construction such as
   AES-256-GCM or XChaCha20-Poly1305, using a fresh nonce for every write.
3. Protect the data key locally with the iOS Keychain / Android Keystore.
4. Show the checksummed random recovery key before enabling encrypted cloud
   sync.
5. On another device, require the recovery key and verify its fingerprint
   before decrypting.
6. Never upload plaintext, the recovery key, or an unwrapped data key.

If the recovery secret is lost, encrypted cloud finance data is unrecoverable.
The UI must explain this before activation and offer an encrypted recovery-key
export.

## Conflict and Realtime rules

- Local writes commit immediately and enter an outbox in the same SQLite
  transaction.
- Push pending operations in stable order with idempotent upserts.
- Pull changes after the last server cursor and merge into SQLite transactionally.
- Use server timestamps for cursors and per-device operation IDs for
  idempotency.
- Use last-write-wins only for independent settings.
- Finance entries merge by entry ID and revision; tombstones win over older
  updates.
- Realtime events trigger a pull. They do not directly mutate UI state.
- Retry transient failures with capped exponential backoff. A verified
  offline-to-online transition bypasses the delay and starts sync immediately.
- Token refresh, reconnect, foregrounding, and manual refresh all trigger sync.

## Shared Preferences removal

Remove `shared_preferences` only after every existing key has a SQLite
equivalent and a one-time migration has run:

- Onboarding completion
- Display name and owner user ID
- OpenAI model selection
- Currency display and custom currencies
- Message bubble style
- Offline STT/TTS selections

For an already-released app, keep the dependency for one migration release,
copy the values into SQLite, mark migration complete, and remove the package in
the following release. Removing it immediately would silently discard current
users' settings.

## Delivery phases

1. [x] Profile-name bootstrap and premium authentication/settings polish.
2. [x] SQLite settings store plus one-time Shared Preferences migration.
3. [x] SQLite finance repository plus JSON-file migration.
4. [x] Account-settings sync and Realtime invalidation.
5. [x] Recovery-key onboarding and encrypted finance sync.
6. [x] Queue restored/legacy local finance rows missing from the encrypted
   backend and remove manual JSON backup/restore controls.
7. [ ] Complete physical two-device conflict, offline, and key-loss testing
   before release.
