# Budget AI

Budget AI is a Flutter personal finance assistant using OpenAI for chat, with
Supabase authentication, offline-first SQLite finance tracking, mandatory
end-to-end encrypted synchronization, and offline speech.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API through the authenticated
  Supabase Edge Function at `openai-responses`. The OpenAI API key is never
  bundled into Flutter.
- The chat model is not user-selectable. The app always uses `gpt-5.4-nano`
  unless overridden from the backend — see "Changing the active AI model" below.
- Chat responses use low reasoning effort and low text verbosity by default, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings are transcribed fully on-device with Sherpa-ONNX and a downloaded quantized Whisper model.
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: hold to record and release to transcribe and send. There is no separate microphone button or microphone setting.
- Spoken replies are generated fully on-device with Sherpa-ONNX and a downloaded Piper voice. Audio never leaves the device; only transcribed text is sent to OpenAI for chat.
- Budget Hub > Offline Speech Models downloads, selects, and removes Whisper STT and Piper TTS models. The mobile-compatible catalog includes Tiny, Base, Small, Medium, and distilled Whisper choices in English and multilingual variants, plus multiple US and British English Piper voices. Downloads show rounded progress, transferred and total size, live speed, and estimated time remaining. No speech model is bundled, so voice chat becomes available after one STT model and one TTS model are downloaded.
- Downloaded models select on tap and remove with a left swipe. Downloaded Piper voices also provide locally generated, zero-API-cost audio previews.
- A reply is spoken only when its user message was submitted through the microphone. Text-submitted messages remain silent.
- All message styles use the default bundled Google Sans font while preserving explicitly branded Boldonse text and monospaced code.

### Changing the active AI model

There is no in-app model picker. The app always requests `gpt-5.4-nano`
(`AIModels.defaultModelId` in `lib/src/chat/ai_models.dart`) unless the
Supabase table `ai_model_config` says otherwise. The table holds a single
global row read by `ActiveModelResolver` (`lib/src/chat/active_model_resolver.dart`)
whenever the chat screen loads or is returned to — no app update or restart
needed to switch models.

To point the app at a different model, run this against the project's
Supabase database (SQL Editor, `psql`, or the `execute_sql`/`apply_migration`
MCP tools):

```sql
-- Switch to a different model.
update public.ai_model_config
set active_model_id = 'gpt-5.6-luna', updated_at = now()
where id = 1;

-- Revert to the hardcoded default (gpt-5.4-nano).
update public.ai_model_config
set active_model_id = null, updated_at = now()
where id = 1;
```

`active_model_id` must match one of the ids in `AIModels.openAIModels`
(`lib/src/chat/ai_models.dart`) — currently `gpt-5.6-luna`, `gpt-5.6-terra`,
`gpt-5.6-sol`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-4.1`,
or `o3`. Any unset row, unknown id, or read failure (offline, RLS, etc.)
silently falls back to `gpt-5.4-nano`, so a bad value can never break chat.

## App flow

- First launch shows onboarding, followed by the Budget AI account flow.
  Currency presets and custom currency creation are available during onboarding
  before sign-in, and the choice is kept locally for the later account flow.
- Email/password registration requires email confirmation. Confirmation codes
  and `budgetai://auth/confirm` links are supported.
- Sign-in sessions restore automatically. Forgot-password and Account password
  changes send secure links that return through
  `budgetai://auth/reset-password`; sign-out lives on the Account screen.
- After confirmation, an encryption gate requires each session to generate a
  recovery key (first device on the account) or restore one (later devices)
  before reaching AI chat. Chat sessions remain local-only; finance data is read
  and written through SQLite and always synchronizes as AES-256-GCM ciphertext
  once the gate is satisfied.
- In Finances, a circular add button beside the keyboard-responsive search
  field opens the shared form for manual entry creation. Tapping an existing
  entry opens the form for editing; save is available in both the AppBar and
  body, while delete stays in the body behind confirmation. There are no swipe
  gestures.
- Chat’s top-right chrome starts with one circular monthly AI-usage indicator,
  followed by equal-size Finances and Budget Hub actions. The indicator tracks
  whichever request/token quota is closest to full and opens a detail sheet
  with both exact counters and a centered UTC renewal date. The Budget mark
  opens Finances directly, leaving the composer prefix-free during normal text
  entry.
- Budget Hub groups the app into a bento-style Quick Actions area for Finances
  and Insights, an Account entry, Preferences for currency, offline speech and
  message style, and App Behavior controls for notifications and the Android
  background service. The dedicated Account screen contains the name editor,
  account identity, secure password-reset action, and sign-out. The currency
  picker has a responsive search field and adjacent circular add action that
  opens a dedicated custom-currency form; custom displays are limited to five
  characters and can be edited or deleted later. The picker reveals the current
  selection on entry, jumps directly to a newly saved custom display, and stays
  open when the selection changes so users can return with Back. The message
  bubble picker currently exposes a searchable bottom control without a custom
  add action. Existing custom styles remain editable and deletable through
  their list actions; the custom editor supports named styles, independent
  bubble/text/pattern colors, five shapes, five patterns, and a floating live
  preview that remains visible while editing.
- Display name, currency, and message style use local-first SQLite
  storage, update the interface immediately, and synchronize in the background.
  Pending changes retry automatically when internet access returns. Onboarding
  completion, notification/background choices, and downloaded speech-model
  selections remain device-local. Granting notifications or Android background
  access during onboarding records the matching local choice, so its Budget Hub
  toggle stays on after account creation or sign-in.
- Existing `finances.json` and Shared Preferences values are imported once into
  SQLite. Legacy or restored local finance rows missing from Supabase are
  automatically queued for encrypted upload when sync is enabled.

## Encrypted synchronization

- End-to-end encryption is mandatory and handled by the encryption gate after
  sign-in, not an opt-in setting.
- The first device on an account generates a random 256-bit account key. It is
  wrapped two ways—by a checksummed `BAI1-...` recovery key and by a
  password-derived key—so a later device can unlock with either the recovery key
  or the account password. The device copy is protected by iOS Keychain or
  Android Keystore.
- Finance payloads are encrypted with AES-256-GCM before upload. Supabase stores
  ciphertext, nonce, authentication tag, revisions, and sync timestamps—not
  plaintext descriptions, categories, or amounts.
- Budget AI and Supabase cannot recover the account key if both the recovery key
  and the account password are lost.
- Realtime events and restored connectivity trigger a SQLite reconciliation;
  UI reads and writes remain local-first.
- Chat history and downloaded speech-model files are never uploaded.

## iOS widget and Siri entry

- The iOS 17 Home Screen widget is one full-width medium summary with the Budget AI splash mark, current balance, income, spending, and up to two newest entries. Its surface, text, and mark invert with the widget's Light/Dark color scheme. It contains no Siri instructions.
- Say “Add an expense in Budget AI” or “Add income in Budget AI” to Siri. Siri asks for the amount and description, saves the entry without presenting the app, and speaks the confirmation.
- Siri-created entries are written to the shared App Group immediately. A Darwin notification and Flutter method channel import them live when Budget AI is running; launch and foreground imports remain the fallback when iOS has suspended the app.
- Widget data synchronization uses `home_widget` 0.9.3. The WidgetKit UI and App Intents remain native Swift because iOS widgets cannot be rendered as live Flutter views.

Before device testing, create the App Group `group.com.muzamil.budget.ai` in the Apple Developer portal and enable it for both the `Runner` and `BudgetAIWidget` identifiers. App Groups require a paid Apple Developer account. Install and open the app once so iOS can register its App Shortcuts, then add Budget AI from the Home Screen widget gallery. Siri voice entry requires iOS 16 or later; the widget requires iOS 17 or later.

On Android, one wide, non-resizable native Home Screen widget reads the same `home_widget` summary keys and follows the app's Light/Dark styling, including the dynamically inverted Budget mark, without voice instructions. Google Assistant custom App Actions accept one-sentence expense and income commands such as “Hey Google, use Budget AI to log 300 for fuel.” Assistant custom intents require an explicit Budget AI invocation and currently support `en-US`. The action opens Budget AI through a deep link, saves the entry, refreshes the widget and open Finances screen, then confirms through Android text-to-speech and a toast.

## Supabase setup

The checked-in Supabase project files live in `supabase/`. The client only
contains the project URL and a modern publishable key; both are public
identifiers. RLS and authenticated user JWTs provide authorization.

```sh
# Authenticate the Supabase CLI once.
npx supabase login

# Store the existing ignored .env value remotely without printing it.
npx supabase secrets set --env-file .env \
  --project-ref bzxsgpsacouvhxepfuca

# Deploy the authenticated streaming proxy.
npx supabase functions deploy openai-responses \
  --project-ref bzxsgpsacouvhxepfuca --use-api
```

In Supabase Dashboard > Authentication:

- Enable Email and password and keep Confirm email enabled.
- Add `budgetai://auth/confirm` and `budgetai://auth/reset-password` to Redirect
  URLs.
- New free-tier projects using Supabase's default SMTP use the standard email
  templates. To use the branded HTML in `supabase/templates/`, first configure
  a custom SMTP provider, then install the confirmation and recovery templates.

The local `supabase/config.toml` contains matching settings for local Supabase.
Never put `OPENAI_API_KEY` in a Flutter asset, Dart define, tracked file, or
mobile build. Delete the local `.env` after the remote secret is verified if it
has no other development purpose.

The AI proxy streams OpenAI events immediately and exposes development timing
headers for quota reservation, OpenAI response headers, and the executing Edge
Function region. Supabase chooses the closest healthy region automatically. To
benchmark a specific supported region without changing the security model,
build with `--dart-define=SUPABASE_FUNCTION_REGION=<aws-region>`. Keep this
empty in production unless measurements show a consistent improvement because
an explicit region disables automatic regional failover.

## Development

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
make apk
```

GitHub Actions runs Flutter CI for pushes to `master` and pull requests whose
base branch is `master`. It uses Flutter 3.44.0, caches the Flutter SDK and
Dart pub packages, then runs formatting, analysis, and Flutter tests. The
cache is restored on later workflow runs, although GitHub-hosted runners still
start as fresh machines.

See `SUPABASE_BACKEND_PLAN.md` for architecture, quota controls, rollout, and
security verification. See `OFFLINE_FIRST_SYNC_PLAN.md` for local persistence,
conflict handling, and encryption boundaries.
