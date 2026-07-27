# Budget AI

Budget AI is a Flutter personal finance assistant using OpenAI for chat, with
Supabase authentication, offline-first SQLite finance tracking, mandatory
end-to-end encrypted synchronization, and offline speech.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API through the authenticated
  Supabase Edge Function at `openai-responses`. The OpenAI API key is never
  bundled into Flutter.
- The default chat model is `gpt-5.6-luna`. Settings exposes the supported OpenAI model catalog, including GPT-5.6 Sol, Terra, and Luna.
- Chat responses use low reasoning effort and low text verbosity by default, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings are transcribed fully on-device with Sherpa-ONNX and a downloaded quantized Whisper model.
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: hold to record and release to transcribe and send. There is no separate microphone button or microphone setting.
- Spoken replies are generated fully on-device with Sherpa-ONNX and a downloaded Piper voice. Audio never leaves the device; only transcribed text is sent to OpenAI for chat.
- Settings > Offline speech models downloads, selects, and removes Whisper STT and Piper TTS models. The mobile-compatible catalog includes Tiny, Base, Small, Medium, and distilled Whisper choices in English and multilingual variants, plus multiple US and British English Piper voices. Downloads show rounded progress, transferred and total size, live speed, and estimated time remaining. No speech model is bundled, so voice chat becomes available after one STT model and one TTS model are downloaded.
- Downloaded models select on tap and remove with a left swipe. Downloaded Piper voices also provide locally generated, zero-API-cost audio previews.
- A reply is spoken only when its user message was submitted through the microphone. Text-submitted messages remain silent.
- All message styles use the default bundled Google Sans font while preserving explicitly branded Boldonse text and monospaced code.

## App flow

- First launch shows onboarding, followed by the Budget AI account flow.
- Email/password registration requires email confirmation. Confirmation codes
  and `budgetai://auth/confirm` links are supported.
- Sign-in sessions restore automatically. Forgot-password links return through
  `budgetai://auth/reset-password`, and Settings includes sign-out.
- After confirmation, an encryption gate requires each session to generate a
  recovery key (first device on the account) or restore one (later devices)
  before reaching AI chat. Chat sessions remain local-only; finance data is read
  and written through SQLite and always synchronizes as AES-256-GCM ciphertext
  once the gate is satisfied.
- In Finances, tapping an entry opens its edit screen directly (view, edit, or
  delete via the app bar); there are no swipe gestures.
- Tap the app bar model name to open the OpenAI model selector.
- Settings includes finances, insights, currency display, OpenAI chat model,
  offline speech models, message bubble style, a notifications toggle, an
  Android background-service toggle, and sign-out.
- Display name, model, currency, and message style use local-first SQLite
  storage, update the interface immediately, and synchronize in the background.
  Pending changes retry automatically when internet access returns. Onboarding
  completion and downloaded speech-model selections remain device-local.
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

See `SUPABASE_BACKEND_PLAN.md` for architecture, quota controls, rollout, and
security verification. See `OFFLINE_FIRST_SYNC_PLAN.md` for local persistence,
conflict handling, and encryption boundaries.
