# Budget AI — Agent Guide

This file is the source of truth for agents working in this repo. Keep it
accurate: **any change that affects what this file describes — the project
structure, features, flows, or architecture — must update this file (and
`README.md`) as part of the same change, before the PR is opened.** A change
that adds/removes/renames files or directories, adds or changes a feature or
screen, or alters a flow or service is not complete until the docs match. If a
change touches nothing the docs describe, no doc update is needed.

Budget AI is a Flutter personal-finance assistant: an OpenAI-powered chat that
logs and edits finances through local tools, offline-first SQLite storage with
mandatory end-to-end encrypted Supabase sync, on-device speech, and native iOS
Siri / Android Assistant + Home Screen widget entry points.

## Project structure

```
lib/
  main.dart                     App bootstrap: init stores/services, run app.
  src/
    auth/                       Auth + mandatory encryption gate
      auth_gate.dart            Routes: loading → recovery → EncryptionGate(chat) → AuthFlow
      auth_screens.dart         Onboarding-styled sign in/up, confirm, reset; AuthTextField
      auth_service.dart         Supabase email/password, sessions, OTP, recovery
      encryption_gate.dart      Mandatory E2E gate: checking → needsSetup → needsRestore → ready
      encryption_setup_screen.dart / encryption_restore_screen.dart
    chat/                       Chat UI + OpenAI Responses streaming + tool loop
      unified_chat_screen.dart  Main chat screen; unified_chat_widgets.dart
      chat_provider*.dart       Streaming client, helpers, tool-call replay
      chat_session_repository.dart  Local-only chat history (SQLite)
      chat_history_screen.dart, chat_system_prompt.dart, chat_model_config.dart
      ai_models.dart            OpenAI model catalog (default gpt-5.4-nano)
      active_model_resolver.dart  Resolves active model from Supabase `ai_model_config`,
                                falling back to the default; no in-app picker
      user_bubble_style_surface.dart  Painted user-bubble styles
      chat_response_markdown.dart, markdown_table_view.dart, streaming_text_reveal.dart
    finances/
      finances_screen.dart      List (month/overall pills, responsive search +
                                manual-add button, balance card); tap → edit
                                screen; no swipe gestures
      finance_entry_edit_screen.dart  Shared create/edit form; AppBar + body save,
                                body delete w/ confirm; auth-style fields;
                                returns FinanceEntryEditResult
      finance_insights_screen.dart    Insights: opens on current month; heatmap clipped
                                to first entry; numberless bars w/ tap-to-reveal popups
      finance_service.dart      Finance domain logic, totals, savings rollover
    settings/
      settings_screen.dart      Name, Finances, Insights, Currency, Speech,
                                Message bubble, Notifications + (Android) Background toggles, Sign out
      bubble_style_screen.dart / bubble_style_settings_service.dart
      currency_picker_screen.dart / currency_settings_service.dart / currency_display_card.dart
      ai_usage_service.dart, user_name_settings_service.dart
      local_speech_models_screen.dart   Download/select/remove STT+TTS models
      permission_preferences_service.dart  Soft on/off for notifications + background
    speech/                     Sherpa-ONNX Whisper STT + Piper TTS (on-device)
    sync/
      account_encryption_service.dart   AES-256-GCM; recovery-key + password-wrapped key
      encrypted_finance_sync_service.dart  Ciphertext-only upload; Realtime invalidation
      account_settings_sync_service.dart   Syncs user_settings (name/currency/bubble)
    storage/                    local_finance_store.dart, local_settings_store.dart (SQLite)
    onboarding/                 First-run onboarding + app showcase
    splash/                     Animated splash
    tools/                      OpenAI finance tools (see below) + registry
    widgets/                    Siri inbox/realtime sync, Android app actions, home-widget sync
    helpers/                    Theme, buttons, sheets, notifications, background services, etc.
supabase/                       Edge function (openai-responses), migrations, email templates, config
```

Root docs: `README.md` (user/setup facing), `SUPABASE_BACKEND_PLAN.md`,
`OFFLINE_FIRST_SYNC_PLAN.md`. Build: `Makefile` (`make apk`), `pubspec.yaml`,
`analysis_options.yaml`.

## Architecture

Flutter with built-in state management (no third-party). Finance data is
offline-first in SQLite; the chat backend is OpenAI-only behind Supabase;
speech is on-device.

- `ResponsesProvider` calls the authenticated Supabase `openai-responses` Edge Function for streaming chat and local finance-tool orchestration. The function validates the user JWT, enforces allowlists and per-user quotas, calls `POST https://api.openai.com/v1/responses`, forwards upstream bytes immediately, and finalizes streamed quota usage in a background task. Debug timing headers expose quota, OpenAI-header, and region measurements. `SUPABASE_FUNCTION_REGION` is an optional benchmarking override; empty preserves automatic regional routing and failover.
- `AuthService` uses Supabase email/password auth with required email confirmation, session restoration, OTP verification, password recovery, and sign-out. `AuthGate` shows onboarding/auth, then wraps the chat in `EncryptionGate`.
- `EncryptionGate` makes end-to-end encryption **mandatory**: every authenticated session must generate a key (first device on the account) or restore one (any later device) before reaching the app.
- `AccountEncryptionService` uses AES-256-GCM. The random 256-bit account key is wrapped two ways: by a checksummed `BAI1-…` recovery key, and by a password-derived key (see migration `20260724120000_add_password_wrapped_key.sql`). The device copy is protected by iOS Keychain / Android Keystore. `EncryptedFinanceSyncService` uploads only authenticated ciphertext and uses Realtime plus verified connectivity restoration as invalidation signals. Never upload the recovery key or plaintext finance payload.
- `LocalSettingsStore` migrates legacy Shared Preferences into SQLite. Account display name, currency, and message bubble style synchronize through `user_settings` via `AccountSettingsSyncService`; onboarding and speech-model selections stay local.
- `LocalFinanceStore` imports the legacy finance JSON file into SQLite and tracks revisions, pending writes, and deletion tombstones. Legacy local rows missing from the remote encrypted table are queued automatically.
- `LocalSpeechService` uses Sherpa-ONNX for on-device Whisper transcription and Piper synthesis. `LocalSpeechModelManager` downloads, selects, persists, and removes model archives from application support storage.
- `OPENAI_API_KEY` exists only as a Supabase Edge Function secret. Flutter contains only the Supabase URL and publishable key; `.env` is not an app asset.
- The model catalog lives in `lib/src/chat/ai_models.dart`; the default is `gpt-5.4-nano`. There is no in-app model picker — `ActiveModelResolver` reads a single global override row from the Supabase `ai_model_config` table (falling back to the default on any missing/invalid/error case) so the model can be changed from the backend without an app update; see README "Changing the active AI model". GPT-5 chat requests use low reasoning effort and low text verbosity; prompts preserve important facts while removing repetition.
- Finance tools (`lib/src/tools/`, registered in `tools.dart`): `finance_add`, `finance_income_add`, `finance_list`, `finance_summary`, `finance_update`, `finance_delete`.

## Feature surface

- **Chat** — streaming OpenAI chat that logs/queries finances via tools. Speech playback is scoped to microphone-originated turns; typed messages never trigger audio. The top-right chrome groups equal-size Finances (Budget mark) and Settings actions; the normal composer has no prefix icon and keeps one contextual trailing action: Send when text exists, hold-to-talk when empty, Stop during a response. The recording pulse still occupies the leading composer slot while recording. The model is not user-facing anywhere in the UI. Chat history is local-only. All styles use the bundled Google Sans font; Boldonse branding and monospaced code are preserved.
- **Finances** — month/overall pill scope, balance card, and a keyboard-responsive keyword-search row with a circular manual-add button. Tapping an entry opens the shared create/edit form directly (no details sheet, no swipe gestures). Save is available in the AppBar and body; existing entries expose body-level delete backed by a confirmation sheet.
- **Insights** — opens scoped to the current month (not Overall). The spending heatmap is clipped to the first tracked entry (header reads "Since <Month Year>" until a full year accrues). The 30-day and month activity charts are numberless bars sized by expense; tap or hold a bar for a transient popup with that day's total and date.
- **Settings** — an always-visible AI usage card (this month's requests/tokens against `ai_user_limits`, with a pulsing skeleton while refreshing) at the top, then inline name editor, Finances, Finance Insights, Currency display, Offline Speech Models, Message bubble (dedicated screen), Notifications toggle, Android Background Service toggle, and Sign out. Bubble-style, currency, and speech-model pickers share one aesthetic (12-radius cards, `outline@0.25`/primary borders, SafeArea + max-width). Encryption is not a settings toggle — it is handled by the mandatory gate.
- **Native entry points** — iOS 17 Home Screen widget + Siri App Intents ("Add an expense/income in Budget AI"); Android Home Screen widget + Google Assistant App Actions. Both write to the shared store and import live via Darwin notification / method channel; the widget UI stays native. See README for App Group and setup details.

## Development rules

- Use `StatefulWidget`, `ValueNotifier`, `ChangeNotifier`, `FutureBuilder`, or `StreamBuilder`; do not add third-party state management.
- Keep provider-specific request shapes isolated in their service/provider files.
- Preserve Responses API output items when replaying tool conversations, including reasoning, function-call, function-call-output, and message items.
- Update `README.md` and this file when setup, models, API surfaces, voice behavior, structure, or features change.
- Never commit `.env`, an OpenAI key, a Supabase secret/service-role key, or a Supabase access token. All OpenAI traffic must remain behind the authenticated Edge Function.
- Never claim a lost recovery key can be recovered. Chat history and downloaded speech-model files must remain excluded from Supabase synchronization.

## Change workflow (required for every change request)

Whenever the user asks for a code change, run the full cycle below — do not
commit straight to `master`. If the user explicitly says to skip it, or for a
trivial non-code edit, you may commit directly; otherwise default to this.

1. **Open a GitHub issue** with `gh issue create` — concise descriptive title,
   body covering what was asked, the problem, and the intended approach.
2. **Branch off an up-to-date `master`** with a descriptive name
   (`feat/…`, `fix/…`, `chore/…`, `docs/…`).
3. **Do the work.** Keep commits focused; run the verification commands below
   and make sure they are clean before committing.
4. **Sync the docs.** If the change touched anything this file or `README.md`
   describes — structure, files/dirs, features, screens, flows, architecture,
   services, or setup — update those docs in the same branch before the PR.
   Skip only when the change genuinely affects nothing the docs cover.
5. **Push and open a PR** into `master` with `gh pr create` — clear title, a
   structured description of what changed and why, and `Closes #<issue>` so the
   issue auto-closes.
6. **Merge the PR** with a merge commit (`gh pr merge <n> --merge`), writing a
   clean merge subject and a summary body of the highlights. Preserve the
   individual commits (do not squash) unless asked otherwise.
7. **Return to `master`** and fast-forward it:
   `git checkout master && git fetch origin && git merge --ff-only origin/master`.

Keep the feature branch after merge unless the user asks to delete it. Use
Conventional Commit prefixes and end commit messages with the co-author and
session trailers already used in this repo's history.

## Verification

```sh
dart format lib test
flutter analyze
flutter test
```
