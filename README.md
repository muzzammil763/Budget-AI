# Budget AI

Budget AI is a Flutter personal finance assistant using OpenAI for chat, with
Supabase authentication, offline-first SQLite finance tracking, mandatory
end-to-end encrypted synchronization, OpenAI voice input, and image chat.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API through the authenticated
  Supabase Edge Function at `openai-responses`. The OpenAI API key is never
  bundled into Flutter.
- The chat model is not user-selectable. The app always uses `gpt-5.6-luna`
  unless overridden from the backend — see "Changing the active AI model" below.
- Chat responses use conservative adaptive reasoning (`none` for exact conversational greetings, `medium` for clearly analytical prompts, and `low` for everything else), low text verbosity, and explicit `top_p: 1.0` sampling, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings use PCM16 WAV and pass through the authenticated `openai-speech` Edge Function to OpenAI `gpt-transcribe`. Chat has voice input only: replies never play audio, automatically or on tap. No ElevenLabs or device TTS dependency is used by chat.
- The composer starts with a **+** button opening a compact, elevated **Camera / Photos** panel with direct icons and content-sized width. Attach up to three images, remove previews, or tap to inspect them. Camera opens capture directly; Photos opens the system gallery. Large photographs are resized automatically to the API limit instead of asking the user to crop them. Images can be sent with text or on their own and remain visible in local chat history.
- Text grows naturally to four lines without a separate expanded editor. The inactive empty or single-line composer is fully pill-shaped; wrapped text and attachments use the multiline corners and put actions below the text.
- The active chat model analyzes receipts and expense images and uses the existing finance tools when asked to log entries. Ambiguous or unreadable details require clarification, and receipt totals must not be added again alongside their line items.
- Requested budget/chart images use the active model's OpenAI image-generation tool (`gpt-image-2`, medium quality, 1024×1024). The assistant retrieves real finance data first. Generated images appear in chat with a zoom viewer. Image generation has separate OpenAI tool charges and requires access on the server's OpenAI project.
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: Chat safely pre-warms the temporary path and existing permission state without activating the microphone, startup reacts immediately on touch-down without replacing the composer, and the recording view appears once audio capture begins. Release transcribes and sends. There is no separate microphone button or microphone setting.
- While Budget AI is preparing a response, the conversation immediately shows `Thinking ...`, smoothly changing to `Budget AI is working ...` after two seconds until the first visible response content or tool call. The bottom composer retains its working status and Stop action. The composer activity mark uses animated bars without a surrounding ring.
- The first launch after this migration removes any previously downloaded
  Whisper files and their retired selection key.
- All message styles use the default bundled Google Sans font while preserving explicitly branded Boldonse text and monospaced code.

### Changing the active AI model

There is no in-app model picker. The app requests the database-selected model
when configured; otherwise it falls back to `gpt-5.6-luna`
(`ActiveModelResolver.defaultModelId` in
`lib/src/chat/active_model_resolver.dart`). The Supabase
table `ai_model_config` holds a single
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

-- Revert to the hardcoded default (gpt-5.6-luna).
update public.ai_model_config
set active_model_id = null, updated_at = now()
where id = 1;
```

`active_model_id` must match one of the ids in
`ActiveModelResolver.supportedModelIds` — currently `gpt-5.6-luna`, `gpt-5.6-terra`,
`gpt-5.6-sol`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-4.1`,
or `o3`. Any unset row, unknown id, or read failure (offline, RLS, etc.)
silently falls back to `gpt-5.6-luna`, so a bad value can never break chat.

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
- In Finances, a circular floating add button opens the shared form for manual entry creation. Tapping an existing
  entry opens the form for editing; save is available in both the AppBar and
  body, while delete stays in the body behind confirmation. There are no swipe
  gestures.
- Chat’s top-right chrome contains equal-size Finances (painted transaction-list mark), Insights (Budget mark), and Budget Hub
  actions; New Chat sits beside History on the left. New Chat instantly opens a fresh draft unless a response is active.
  Chat preloads monthly usage and authorized admin data in the background
  without delaying Budget Hub navigation. A
  circular AI-usage action lives in the Budget Hub AppBar, tracks whichever
  request/token quota is closest to full, and opens immediately with
  loading placeholders, exact request/token/Fast counters, and a centered UTC
  renewal date. Administratively blocked accounts show a red indicator and an
  explanatory sheet. The Budget mark
  opens Finances directly; the composer + action opens image attachments.
- Finance tool calls appear inline in assistant turns with live status. A
  single call shows its named expandable row; consecutive calls use an
  expandable grouped summary. Expanding reveals the arguments and result while
  preserving the response text in chronological order.
- OpenAI request context stays bounded: the active user turn preserves its
  complete reasoning/tool-call chain, while completed turns resend only the 16
  most recent user/assistant dialogue items. Finance data is fetched on demand
  through tools instead of attaching an always-on finance snapshot to every
  request and tool round.
- Budget Hub groups the app into a bento-style Quick Actions area for Finances
  and Insights, inline Account controls for the editable name, read-only email,
  and secure password reset, Preferences for currency and message style, and
  App Behavior controls for Fast Responses, notifications,
  and the Android background service. Authorized admins also get user AI
  access and monthly quota controls plus a dedicated, confirmed local-preference screen;
  superadmins additionally manage roles. Fast Responses is off by default and
  requests OpenAI Fast mode (`service_tier: "fast"`), which lowers latency but
  carries higher per-token pricing. The backend grants 100 Fast requests per
  UTC month by default, then transparently falls back to Standard while overall
  request/token limits still apply. A final Danger Zone contains sign-out and permanent
  account deletion. Deletion requires entering `DELETE MY ACCOUNT` with the
  inline keyboard and accepting one final warning; account-owned encrypted
  cloud data is deleted with the account while device-only data remains local. The currency
  picker has borderless AppBar search and a circular floating add action that
  opens a dedicated custom-currency form; custom displays are limited to five
  characters and can be edited or deleted later. The picker reveals the current
  selection on entry, jumps directly to a newly saved custom display, and stays
  open when the selection changes so users can return with Back. The message
  bubble picker has no search or custom add action. Its second preset is Outline: the Primary bubble shape with a
  transparent fill and 1.5 px primary-color border. Bubble content uses 12 px
  padding on every side. Existing custom styles remain editable and deletable through
  their list actions; the custom editor supports named styles, independent
  bubble/text/pattern colors, five shapes, five patterns, and a floating live
  preview that remains visible while editing.
- Display name, currency, and message style use local-first SQLite
  storage, update the interface immediately, and synchronize in the background.
  Pending changes retry automatically when internet access returns. Onboarding
  completion and Fast Responses and notification/background choices remain
  device-local. Granting notifications or Android background
  access during onboarding records the matching local choice, so its Budget Hub
  toggle stays on after account creation or sign-in. Turning Notifications off
  suppresses future delivery and clears notifications already shown by the app.
- Signing out clears the previous user's local finances, chat history,
  preferences, encryption key, widget data, and legacy storage while preserving
  the completed-onboarding flag.
- Budget Hub exposes Replay onboarding. It opens the same five-page onboarding
  experience with a route-level Back control; Back or completing the final page
  returns to Budget Hub instead of restarting the authentication flow.
- When a response finishes while Budget AI is away from the foreground chat,
  its notification uses the complete response converted from Markdown into
  readable plain text. Android exposes that content through its expandable
  large-text notification; the operating system still controls how much is
  visible in the collapsed notification and on the lock screen. Leaving the
  app during an active response also disables the buffered typewriter reveal,
  requests iOS background execution time, and schedules the completion
  notification before releasing that task. iOS ultimately controls the
  available background time, so unusually long responses can still resume
  after the app returns.
- Chat Markdown tables left-align every header and value column for a
  consistent reading edge, including numeric comparison columns.
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
- Chat history and images are stored locally in SQLite and excluded from account sync. Relevant conversation context and attached images pass through the authenticated Responses proxy to OpenAI to answer requests; audio passes through the speech proxy for transcription. Image inputs are limited to 1600 pixels on the longest edge: small PNGs remain lossless up to 384 KB, and larger images become metadata-free JPEGs capped at 768 KB. Only the latest three image inputs remain in provider context; older images stay visible locally and can be attached again for analysis. Account exit clears local chat data.
- iOS camera/gallery access uses `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`. Android uses the system picker/camera and recovers picker results if the activity is recreated. Test camera capture and gallery permissions on a physical device.

## iOS widget and Siri entry

- The iOS 17 Home Screen widget is one full-width medium summary with the Budget AI splash mark, monthly spending and up to two newest expenses. Its surface, text, and mark invert with the widget's Light/Dark color scheme. It contains no Siri instructions.
- Say “Add an expense in Budget AI” to Siri. Siri asks for the amount and description, saves the entry without presenting the app, and speaks the confirmation.
- Siri-created entries are written to the shared App Group immediately. A Darwin notification and Flutter method channel import them live when Budget AI is running; launch and foreground imports remain the fallback when iOS has suspended the app.
- Widget data synchronization uses `home_widget` 0.9.3. The WidgetKit UI and App Intents remain native Swift because iOS widgets cannot be rendered as live Flutter views.

Before device testing, create the App Group `group.com.muzamil.budget.ai` in the Apple Developer portal and enable it for both the `Runner` and `BudgetAIWidget` identifiers. App Groups require a paid Apple Developer account. Install and open the app once so iOS can register its App Shortcuts, then add Budget AI from the Home Screen widget gallery. Siri voice entry requires iOS 16 or later; the widget requires iOS 17 or later.

On Android, one wide, non-resizable native Home Screen widget reads the same `home_widget` summary keys and follows the app's Light/Dark styling, including the dynamically inverted Budget mark, without voice instructions. Google Assistant custom App Actions accept one-sentence expense commands such as “Hey Google, use Budget AI to log 300 for fuel.” Assistant custom intents require an explicit Budget AI invocation and currently support `en-US`. The action opens Budget AI through a deep link, saves the entry, refreshes the widget and open Finances screen, then confirms through Android text-to-speech and a toast.

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
mobile build. The same Supabase secret used by chat powers transcription; deploy
the authenticated speech proxy with:

```sh
supabase functions deploy openai-speech
supabase functions deploy openai-responses
```

Restrict the Google key to Cloud Speech-to-Text and Cloud Text-to-Speech. Delete
the local `.env` after remote secrets are verified if it has no other purpose.

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

### Monthly finance insights

Budget AI supports manual expense and income entry, editing, and deletion. Finances lists both types with red expense and green income amounts. The shared monthly and Overall card shows separate Expenses and Income totals with red outgoing and green incoming icons and normal card-colored amounts. No balances, Saved/Overused, or rollovers are shown. Chat and native shortcuts log expenses; image receipts, spending charts, search, and expense editing remain available.

Finances and the shared summary include existing income; all reporting excludes internal savings/deficit transfers. Startup no longer creates or recalculates rollovers. Existing records remain stored without a destructive migration, while expense views, tools, and widget exports use actual expenses only.

Finance Insights retains expense category breakdowns, daily trends, heatmaps, and monthly spending highlights. Each nonempty month has a **Monthly Summary** card. Generate/Regenerate uses fresh expense totals, categories, and daily spending only. A new expense-summary cache namespace prevents old income/balance summaries from appearing.

Summaries are stored per account/month in local Shared Preferences and cleared at account exit. They are excluded from Supabase synchronization. Generation uses the existing authenticated Responses proxy, active model, and AI quota; the OpenAI key remains server-only. No new backend deployment is required for this feature.

Finances and Insights share `expense_summary_card.dart`: the same rounded gradient card shows separate scoped expense and income totals, expense entry count, distinct expense days, and daily expense average. Income-only and empty scopes also show both totals. Daily average covers calendar days from the first scoped expense through today (or the last day of a past month); empty scopes show zero. Search filters the list without changing the scope summary.

Image input uses Responses `input_image` parts with base64 data URLs, as documented at https://developers.openai.com/api/docs/guides/images-vision. Chat allows 90 seconds before the first visible image-analysis content, including retries with existing image context; inactivity timeout cancels HTTP before awaiting stream cleanup. Attachment strips use their content width with 64-pixel composer and 72-pixel message previews, retaining removal and zoom. The shared spending card displays explicit Overall dates and a 1–today range for the current month.

Attachment composer rows align left, with up to three previews side by side; user text uses natural start alignment beneath image previews, sharing their leading edge inside a right-positioned bubble. Small screenshots stay PNG; larger decoded images become metadata-free JPEGs capped at 768 KB using the `image` package in a background isolate, avoiding photo-to-PNG payload inflation.

Request failures include sanitized JSON diagnostics: payload size, attachment MIME/encoded size, uploaded bytes, last confirmed proxy/response stage, and elapsed time. Inactivity timeouts surface immediately instead of silently retrying; stream cleanup is bounded to two seconds. Diagnostics never include prompts, image bytes, or credentials and do not assume OpenAI received an image before response events are observed.

Only explicit Stop actions display Request Cancelled. Internal cancellations retain an interruption message and request diagnostics; cancellation-cleanup exceptions cannot mask the original failure.

Finances and Currency use a Cupertino search action that replaces the AppBar title with an unfilled, borderless `Search ...` input. Search mode has a non-tappable leading search icon; its close action clears the query and restores normal navigation. Chat History uses the same non-tappable search prefix while searching. Add controls retain their circular primary-color design as floating buttons. The chat composer has a compact 48-pixel minimum height, the standard surface with Material elevation 12, and no animated or static border. The empty chat contains 20 shuffled finance starter prompts, all fully revealed by the end of the entrance animation.

Outgoing chat bubbles occupy at most 86% of the screen width. Their images and captions share a leading edge; multiline text uses natural start alignment while the bubble itself remains on the right. The Finances shortcut paints a transaction list with incoming and outgoing arrows, shared by chat navigation and the Budget Hub Quick Actions card.

Voice requests explicitly send `action: "transcribe"` for compatibility with older speech deployments. Recording/transcription has a leading cancel control; temporary audio is cleaned up on success, cancellation, empty results, and failure. Empty transcripts restore the composer. Explicit chart/image requests enable the hosted image tool, including plural wording, and instruct the model to retrieve recorded spending before rendering an image. Deploy both `openai-speech` and `openai-responses` when updating the media contract: stale deployments can reject requests with `invalid_action` or `unsupported_tool`.
