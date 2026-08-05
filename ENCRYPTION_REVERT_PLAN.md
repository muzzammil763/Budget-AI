# Encryption revert plan

**Status:** Encryption is currently **disabled** on this branch
(`feat/bank-first-plaid-sync`), as of 2026-08-05.

## What changed

Finance entries were previously encrypted client-side (AES-256-GCM) before
being synced to Supabase, via `EncryptedFinanceSyncService` +
`AccountEncryptionService`, gated behind `EncryptionGate` on every
authenticated session. For easier local/dev inspection while building the
bank-sync feature, this was swapped for a plaintext path:

- New table `public.plain_finance_entries` (migration
  `supabase/migrations/20260805120000_create_plain_finance_entries.sql`) —
  same shape as `encrypted_finance_entries` but with a single `payload jsonb`
  column instead of `ciphertext`/`nonce`/`mac`.
- New service `lib/src/sync/plain_finance_sync_service.dart` — a structural
  copy of `EncryptedFinanceSyncService` with the encrypt/decrypt step
  removed.
- 3 wiring points switched to the new service/table (see below).

**Nothing about the existing encrypted path was touched or deleted.**
`EncryptedFinanceSyncService`, `AccountEncryptionService`, `EncryptionGate`,
`EncryptionSetupScreen`, `EncryptionRestoreScreen`, the
`encrypted_finance_entries` / `user_encryption` tables, and their migrations
are all still in place, just unreferenced. Reverting is only the 3 edits
below, in reverse.

## The 3 wiring points to flip back

### 1. `lib/main.dart`

```dart
// current (plaintext)
import 'package:budget_ai/src/sync/plain_finance_sync_service.dart';
...
await PlainFinanceSyncService.instance.initialize();

// revert to (encrypted)
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
...
await EncryptedFinanceSyncService.instance.initialize();
```

### 2. `lib/src/auth/auth_gate.dart`

```dart
// current (plaintext) — no import of encryption_gate.dart
if (auth.isAuthenticated) {
  return const UnifiedChatScreen(config: ChatModelConfig.openAI);
}

// revert to (encrypted) — restore the import too:
// import 'package:budget_ai/src/auth/encryption_gate.dart';
if (auth.isAuthenticated) {
  return const EncryptionGate(
    child: UnifiedChatScreen(config: ChatModelConfig.openAI),
  );
}
```

### 3. `lib/src/finances/finances_screen.dart`

```dart
// current (plaintext)
import 'package:budget_ai/src/sync/plain_finance_sync_service.dart';
...
PlainFinanceSyncService.instance.status.addListener(...)
PlainFinanceSyncService.instance.status.removeListener(...)
PlainFinanceSyncService.instance.status.value == 'Syncing…'

// revert to (encrypted)
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
...
EncryptedFinanceSyncService.instance.status.addListener(...)
EncryptedFinanceSyncService.instance.status.removeListener(...)
EncryptedFinanceSyncService.instance.status.value == 'Syncing…'
```

That's the entire revert. `plain_finance_sync_service.dart` and the
`plain_finance_entries` table can then either be deleted, or left in place
unused (harmless — RLS-scoped per user like every other table here). Deleting
the table requires a new migration (`drop table public.plain_finance_entries;`);
this file doesn't do that automatically since it's your call whether to keep
it around for reference.

## Important caveat for whoever reverts

Any account that signed up **while encryption was disabled** has no entry in
`user_encryption`. The moment `EncryptionGate` is restored, those accounts
will hit the `needsSetup` state on next launch — expected, same as any
first-time setup — and will need to re-sync from their local (already
plaintext) SQLite data, exactly like a brand-new account would. This is not
data loss: `LocalFinanceStore` always holds the plaintext source of truth;
only the Supabase copy needs re-encrypting and re-pushing, which
`EncryptionSetupScreen` already does automatically.
