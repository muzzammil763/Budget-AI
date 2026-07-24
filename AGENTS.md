# Budget AI Developer Guide

## Architecture

Budget AI is a Flutter application using built-in Flutter state management.
Finance data is stored offline-first in SQLite with optional end-to-end
encrypted Supabase synchronization. Chat sessions remain local-only.

The chat backend is OpenAI-only, while authentication is Supabase and speech is
local:

- `ResponsesProvider` calls the authenticated Supabase `openai-responses` Edge Function for streaming chat and local finance-tool orchestration. The function validates the user JWT, enforces allowlists and per-user quotas, calls `POST https://api.openai.com/v1/responses`, forwards upstream bytes immediately, and finalizes streamed quota usage in a background task. Debug timing headers expose quota, OpenAI-header, and region measurements. `SUPABASE_FUNCTION_REGION` is an optional benchmarking override; empty preserves automatic regional routing and failover.
- `AuthService` uses Supabase email/password auth with required email confirmation, session restoration, OTP verification, password recovery, and sign-out. `AuthGate` follows first-run onboarding and protects AI chat.
- `LocalSettingsStore` migrates legacy Shared Preferences into SQLite. Account
  display name, OpenAI model, currency, and message bubble style synchronize
  through `user_settings`; onboarding and speech-model selections stay local.
- `LocalFinanceStore` imports the legacy finance JSON file into SQLite and
  tracks revisions, pending writes, and deletion tombstones. Legacy local rows
  missing from the remote encrypted table are queued automatically.
- `AccountEncryptionService` generates a random 256-bit recovery key, protects
  the device copy with Keychain/Keystore, and uses AES-256-GCM.
  `EncryptedFinanceSyncService` uploads only authenticated ciphertext and uses
  Realtime plus verified connectivity restoration as invalidation signals.
  Never upload the recovery key or plaintext finance payload.
- `LocalSpeechService` uses Sherpa-ONNX for on-device Whisper transcription and Piper speech synthesis. `LocalSpeechModelManager` downloads, selects, persists, and removes model archives from application support storage.
- `OPENAI_API_KEY` exists only as a Supabase Edge Function secret. Flutter contains only the Supabase URL and publishable key; `.env` is not an app asset.
- The model catalog lives in `lib/src/chat/ai_models.dart`; the default is `gpt-5.6-luna`.
- GPT-5 chat requests use low reasoning effort and low text verbosity. Prompts preserve important facts while removing repetition and optional background.
- Speech playback is scoped to microphone-originated turns. Typed messages never trigger automatic audio.
- The composer uses one contextual action: Send when text exists, always-available hold-to-talk when empty, and Stop during an active response. Releasing a voice hold transcribes and sends immediately.
- Settings exposes a chat-model picker and an offline speech-model manager with mobile-compatible Tiny, Base, Small, Medium, and distilled Whisper variants and multiple US and British English Piper voices. Downloads report transferred and total size, live speed, and estimated time remaining. Voice chat requires one downloaded STT model and one downloaded TTS model; model selections persist locally. Downloaded models use swipe removal, and downloaded Piper voices provide locally generated previews.
- All message styles use the bundled Google Sans font at the app-theme level. Explicit Boldonse branding and monospaced code remain unchanged.
- `home_widget` mirrors finance summaries and entries into the `group.com.muzamil.budget.ai` App Group. The native iOS 17 `BudgetAIWidget` target renders one medium-width, app-styled financial summary whose surface, text, and splash mark follow the widget Light/Dark color scheme, with no voice instructions.
- Native App Intents expose “Add an expense in Budget AI” and “Add income in Budget AI” to Siri. Siri stores entries in the shared App Group, speaks a system confirmation, and posts a Darwin notification for live Flutter import. Launch and foreground imports cover periods when iOS has suspended the app.
- Android exposes matching `home_widget` summary data through one wide, non-resizable `BudgetAIWidgetProvider` layout whose background, text, and splash mark use Light/Dark resource palettes, with no voice instructions. Google Assistant custom App Actions deep-link amount and description parameters into Flutter; successful actions update local finance data and use Android text-to-speech for confirmation.

## Development rules

- Use `StatefulWidget`, `ValueNotifier`, `ChangeNotifier`, `FutureBuilder`, or `StreamBuilder`; do not add third-party state management.
- Keep provider-specific request shapes isolated in their service/provider files.
- Preserve Responses API output items when replaying tool conversations, including reasoning, function-call, function-call-output, and message items.
- Update `README.md` and this file when setup, models, API surfaces, voice behavior, or architecture changes.
- Never commit `.env`, an OpenAI key, a Supabase secret/service-role key, or a Supabase access token. All OpenAI traffic must remain behind the authenticated Edge Function.
- Never claim a lost recovery key can be recovered. Chat history and downloaded
  speech-model files must remain excluded from Supabase synchronization.

## Change workflow (required for every change request)

Whenever the user asks for a code change, run the full cycle below — do not
commit straight to `master`. If the user explicitly says to skip it, or for a
trivial non-code edit, you may commit directly; otherwise default to this.

1. **Open a GitHub issue** with `gh issue create` — concise descriptive title,
   body covering what was asked, the problem, and the intended approach.
2. **Branch off an up-to-date `master`** with a descriptive name
   (`feat/…`, `fix/…`, `chore/…`).
3. **Do the work.** Keep commits focused; run the verification commands below
   and make sure they are clean before committing.
4. **Push and open a PR** into `master` with `gh pr create` — clear title, a
   structured description of what changed and why, and `Closes #<issue>` so the
   issue auto-closes.
5. **Merge the PR** with a merge commit (`gh pr merge <n> --merge`), writing a
   clean merge subject and a summary body of the highlights. Preserve the
   individual commits (do not squash) unless asked otherwise.
6. **Return to `master`** and fast-forward it:
   `git checkout master && git merge --ff-only origin/master`.

Keep the feature branch after merge unless the user asks to delete it. Use
Conventional Commit prefixes and end commit messages with the co-author and
session trailers already used in this repo's history.

## Verification

```sh
dart format lib test
flutter analyze
flutter test
```
