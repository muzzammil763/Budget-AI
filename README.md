# Budget AI

Budget AI is a Flutter personal finance assistant using OpenAI for chat, with
Supabase authentication, offline-first SQLite finance tracking with opt-in
Supabase Cloud Sync and backup files, OpenAI voice input, and image chat.

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
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: Chat safely pre-warms the temporary path and existing permission state without activating the microphone, startup reacts immediately on touch-down without replacing the composer, and the recording view appears once audio capture begins. Release transcribes and sends. There is no separate microphone button or microphone setting.
- While Budget AI is preparing a response, the conversation immediately shows `Thinking ...`, smoothly changing to `Budget AI is working ...` after two seconds until visible response content, or the first tool call when tool rows are enabled. The bottom composer retains its working status and Stop action. The composer activity mark uses animated bars without a surrounding ring.
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
- Email/password registration is confirmed with a 6-digit code. The signup
  email (`supabase/templates/confirmation.html`) shows only the code; the
  "Enter your code" screen has six boxes that verify automatically once full,
  plus Paste code, Open mail, and a 60-second Resend.
- Auth emails use branded templates in `supabase/templates/` (app-style
  monochrome design, Boldonse heading, hosted logo at
  `https://budgetai-app.pages.dev/email/app-icon.png`, light and dark). Paste them
  into Supabase Dashboard → Authentication → Emails → Templates. Password
  reset stays a link to `budgetai://auth/reset-password`.
- Sign-in sessions restore automatically. Forgot-password and Account password
  changes send secure links that return through
  `budgetai://auth/reset-password`; sign-out lives on the Account screen.
- After confirmation, sign-in leads straight to AI chat. Chat sessions remain
  local-only; finance data is read and written through SQLite and, only when
  the account has Cloud Sync on, synchronizes as plain rows in the Supabase
  `finance_entries` table.
- In Finances, a circular floating add button opens the shared form for manual entry creation. Tapping an existing
  entry opens the form for editing; save is available in both the AppBar and
  body, while delete stays in the body behind confirmation. There are no swipe
  gestures.
- Chat’s top-right chrome contains equal-size Finances (painted transaction-list mark), Insights (Budget mark), and Budget Hub
  actions; New Chat sits beside History on the left. New Chat instantly opens a fresh draft unless a response is active.
  Chat preloads monthly usage and authorized admin data in the background
  without delaying Budget Hub navigation. A
  circular AI-usage action lives in the Budget Hub AppBar, tracks whichever
  message/token quota is closest to full, and opens immediately with
  loading placeholders, exact message/token/Fast counters, and a centered UTC
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
  inline keyboard and accepting one final warning; account-owned
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
- On Android, bubble styles follow the Premium plan: Free has Classic and
  Outline, Lite adds Ledger, Savings, and Cash flow, Plus adds Growth, Receipt,
  and Night budget, and Pro adds Vault, Paper curl, Sketch frame, and custom
  styles. Locked styles still show their full preview under FREE/LITE/PLUS/PRO
  headers; tapping one opens the paywall on that plan, and the paywall's
  comparison lists bubble styles per plan. A style from a lapsed plan stays
  saved while chat shows Classic. iOS keeps every style.
- Display name, currency, and message style use local-first SQLite
  storage, update the interface immediately, and synchronize in the background.
  Pending changes retry automatically when internet access returns. Onboarding
  completion and Fast Responses and notification/background choices remain
  device-local. Granting notifications or Android background
  access during onboarding records the matching local choice, so its Budget Hub
  toggle stays on after account creation or sign-in. Turning Notifications off
  suppresses future delivery and clears notifications already shown by the app.
- Signing out clears the previous user's local finances, chat history,
  preferences, widget data, and legacy storage while preserving
  the completed-onboarding flag. When that would erase entries with no cloud
  copy (Cloud Sync off, or changes not uploaded yet), sign-out first shows
  "Keep Your Entries Safe": Back Up Entries, Turn On Cloud Sync (or Sync Now)
  & Sign Out, or Sign Out & Erase N entries. Delete Account offers a backup
  first whenever the device has entries.
- Budget Hub → Preferences → Home Screen Widgets previews every widget with
  the user's own numbers (sample numbers until the first entry). On Android
  launchers that support pinning (including Samsung One UI), Add to Home
  Screen opens the system "Add to Home screen?" sheet and the card shows "On
  Home Screen" once placed; elsewhere, and on iOS, it shows step-by-step
  instructions (iOS has no API to add widgets from an app).
- Cancelling a password reset started from Budget Hub → Change Password keeps
  the account signed in with its local entries; a reset started from the
  sign-in screen returns to sign-in.
- Budget Hub → Your Data: Cloud Sync toggle, Back Up Entries (saves
  `BudgetAI-Backup-YYYY-MM-DD.json` wherever the user picks via the system
  save dialog; the last backup date is shown), and Restore From Backup
  (merges a backup by entry id; identical entries are skipped).
- Budget Hub has an About & Legal section: About (version, features, support at
  budgetaitracker@gmail.com), Privacy Policy, and Terms & Conditions, styled like
  the rest of the app.
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
- Every finished AI reply shows Copy and Report. Report asks for a reason
  (inaccurate, harmful, inappropriate, other) and an optional note, then saves
  it to the insert-only `ai_reports` table for review in the Supabase dashboard.
- Chat Markdown tables left-align every header and value column for a
  consistent reading edge, including numeric comparison columns.
- Existing `finances.json` and Shared Preferences values are imported once into
  SQLite. Legacy or restored local finance rows missing from Supabase are
  automatically queued for upload when sync is enabled.

## Synchronization

- Finance Cloud Sync is opt-in per account (`users.finance_sync_enabled`,
  default false; migration `20261016120000_add_finance_sync_opt_in.sql` turns
  it on for every account that existed before). The choice syncs with the
  other account settings, and a device only pushes the column once it knows
  the account's value, so a fresh install never overwrites it. With sync off,
  `FinanceSyncService` stays detached and local writes stay pending; turning
  it on uploads them. Turning it off stops future uploads; rows already in
  `finance_entries` stay until account deletion. Deploy the migration before
  shipping a client that writes the column.
- Mobile OSes give apps no uninstall hook, so the app cannot prompt at
  uninstall time; the sign-out warning, Budget Hub backup, and Android Auto
  Backup are the safeguards.
- Android Auto Backup is on but limited to the finance database
  (`budget_ai_finance.db` and its WAL/journal) by
  `res/xml/finance_backup_rules.xml` (Android 6–11) and
  `res/xml/finance_data_extraction_rules.xml` (Android 12+ cloud backup and
  device transfer). Chat history, sessions, and settings are never backed up.
  The finance database records its owner (`store_meta.owner_user_id`); when a
  different account signs in after a restore, those entries are cleared
  before they can be shown or uploaded, and finance sync never uploads
  entries it has not confirmed as the signed-in account's.
- Finance entries sync as plain rows in `finance_entries` (one column per
  field: type, amount, category, description, date, has_time, created_at, plus
  revision, tombstone, and timestamp metadata), protected per user by
  row-level security. End-to-end encryption has been retired.
- Account settings sync through `users`; roles live in `user_roles`; AI quotas
  use `user_ai_limits`, `ai_usage`, `ai_requests`, and `ai_model_config`.
- Sign-up is email + password confirmed by a 6-digit email code; login is email +
  password and goes straight to the app with no key or unlock step. Earlier
  end-to-end encryption has been fully removed.
- Remote reads page in 1000-row chunks, since Supabase caps a single select at
  `max_rows`.
- Realtime events and restored connectivity trigger a SQLite reconciliation;
  UI reads and writes remain local-first.
- Chat history and images are stored locally in SQLite and excluded from account sync. Relevant conversation context and attached images pass through the authenticated Responses proxy to OpenAI to answer requests; audio passes through the speech proxy for transcription. Image inputs are limited to 1600 pixels on the longest edge: small PNGs remain lossless up to 384 KB, and larger images become metadata-free JPEGs capped at 768 KB. Only the latest three image inputs remain in provider context; older images stay visible locally and can be attached again for analysis. Account exit clears local chat data.
- iOS camera/gallery access uses `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`. Android uses the system picker/camera and recovers picker results if the activity is recreated. Test camera capture and gallery permissions on a physical device.

## iOS widgets

Budget AI ships eight iOS 17 Home Screen widgets plus Lock Screen widgets, all
following the app's monochrome style with red expenses and green income, in
Light and Dark:

- **Budget AI** (wide): this month's expenses, income, and entry count with
  the two newest expenses.
- **Expenses** and **Income** (small): one large month total with its entry
  count. **Income & Expenses** (small) shows both with proportion bars. These
  three have a `‹ Oct ›` chip in the corner; the arrows switch months in place
  without opening the app, stopping at the first month with data and at the
  current month.
- **Recent Expenses** (medium): the last five expenses with day and amount.
- **Today's Expenses** (large): today's total, entry count, and each expense.
- **This Month vs Last** (small): both months' expenses as bars with the
  percentage change.
- **Top Categories** (medium): the month's four largest expense categories
  with amount, share, and bars, with the same `‹ Oct ›` month arrows.
- **Lock Screen**: a circular ring of this month's spending against last
  month, a rectangular month expenses/income card, and an inline "Today …
  spent" line.

Taps open the matching screen after sign-in, on top of chat so Back returns
there:

| Widget | Tap opens |
| --- | --- |
| Budget AI, Recent Expenses, Today's Expenses, Lock Screen | Finances on the current month |
| Expenses, Income, Income & Expenses | Finances on the month the widget shows (including a month picked with ‹ ›) |
| A single expense row (wide, Recent, Today) | Finances on that entry's month with its editor open |
| This Month vs Last | Insights on the current month |
| Top Categories | Insights on the month the widget shows |

Widget links use `budgetai://widget/<finances|insights>?homeWidget&month=yyyy-MM&entry=<id>`
and are handled by `HomeWidgetLaunch`. Android's widget tap opens Finances.

Widgets read every actual expense and income entry from the App Group, written
by `home_widget` whenever finances change. Budget AI exposes no Siri or
Shortcuts actions; the month-arrow intent is hidden from the Shortcuts app.

Before device testing, create the App Group `group.com.muzamil.budget.ai` in the Apple Developer portal and enable it for both the `Runner` and `BudgetAIWidget` identifiers. App Groups require a paid Apple Developer account. Install and open the app once, then add Budget AI widgets from the Home Screen widget gallery. Widgets require iOS 17 or later.

On Android, the same eight Home Screen widgets are native `RemoteViews` providers (`BudgetAIWidgetProvider.kt`): the wide summary, small Expenses / Income / Income & Expenses with per-widget ‹ › month arrows, Recent Expenses, Today's Expenses, This Month vs Last, and Top Categories. They read the shared `budget_ai_widget_entries` list, follow Light/Dark through resource colors, draw headline amounts in Boldonse as tinted bitmaps (launchers ignore app fonts in widgets), and use the same `budgetai://widget/...` tap links. Each widget has a sample-filled picker preview. Google Assistant custom App Actions accept one-sentence expense commands such as “Hey Google, use Budget AI to log 300 for fuel.” Assistant custom intents require an explicit Budget AI invocation and currently support `en-US`. The action opens Budget AI through a deep link, saves the entry, refreshes the widget and open Finances screen, then confirms through Android text-to-speech and a toast.

## Premium (Android)

Android sells Budget AI Premium through Google Play, using RevenueCat
(`purchases_flutter`) with a custom paywall. iOS has no paywall yet and keeps
the previous default limits (`legacy` plan).

| Plan | AI | Messages / month | Tokens | Fast | Deep analysis | Price |
| --- | --- | --- | --- | --- | --- | --- |
| Free | Swift AI | 5 | 60K | — | — | — |
| Lite | Swift AI | 100 | 500K | — | — | $1.99/mo · $19.99/yr |
| Plus | Smart AI | 150 | 750K | 15 | — | $6.99/mo · $64.99/yr |
| Pro | Smart AI | 200 | 1M | 20 | 40 on Expert AI (within the 200) | $11.99/mo · $109.99/yr |

- A message is one user turn: its tool rounds, automatic continuations, voice
  transcription, and chat title share the client's `user_turn_id` and count
  once. A Monthly Summary is its own message.
- The server is the source of truth. `plan_limits` holds the numbers (editable
  in the dashboard), `user_subscriptions` mirrors RevenueCat, and
  `reserve_ai_message_request` resolves the plan (admins get Pro), picks the
  model, and refuses with `premium_required` (Free) or `plan_limit_reached`
  as HTTP 402. Admin quota overrides apply only when `quota_override` is set.
- The app reads its plan with the `get_my_ai_plan` RPC. A blocked chat send,
  mic hold, receipt, or Monthly Summary opens a Premium sheet that leads to the
  paywall (Pro shows the reset date instead); a 402 never shows a chat error; after the free message a composer notice offers Premium.
  Budget Hub shows a Premium card, and Fast Responses is locked on Free/Lite.
- Play products `budget_ai_lite`, `budget_ai_plus`, `budget_ai_pro`, each with
  `monthly` and `yearly` base plans, map to RevenueCat entitlements `lite`,
  `plus`, `pro`. The RevenueCat app user ID is the Supabase user id. Upgrades
  apply now with proration; downgrades wait for renewal.
- Complimentary access (for example the Play reviewer account): insert a
  `user_subscriptions` row with `tier = 'pro'`, `status = 'active'`,
  `expires_at = null`, `store = 'complimentary'`. The webhook never revokes it.

Setup: put the public SDK key in `.env` as `REVENUECAT_ANDROID_KEY=goog_...`
(`make aab`/`make apk` pass it as a Dart define). Set the server secrets
`REVENUECAT_SECRET_KEY` and `REVENUECAT_WEBHOOK_SECRET`, deploy
`revenuecat-webhook`, and in RevenueCat add the webhook URL
`https://<project>.supabase.co/functions/v1/revenuecat-webhook` with the same
Authorization value as `REVENUECAT_WEBHOOK_SECRET`.

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
supabase functions deploy revenuecat-webhook
```

Delete the local `.env` after remote secrets are verified if it has no other purpose.

The AI proxy streams OpenAI events immediately and exposes development timing
headers for quota reservation, OpenAI response headers, and the executing Edge
Function region. Supabase chooses the closest healthy region automatically. To
benchmark a specific supported region without changing the security model,
build with `--dart-define=SUPABASE_FUNCTION_REGION=<aws-region>`. Keep this
empty in production unless measurements show a consistent improvement because
an explicit region disables automatic regional failover.

## Website

`website/` is an Astro static site (landing page, `/privacy`, `/terms`,
`/delete-account`) for Cloudflare Pages. Its legal text in
`website/src/data/legal.ts` mirrors `lib/src/settings/legal_screens.dart`;
change both together.

The landing page ends with a Screenshots section: an Android / iPhone switch
over a swipeable strip of the full store slides from `store-listing/`
(copied into `website/src/assets/store/`).

```sh
cd website
npm install
npm run dev        # http://localhost:4321
npm run build      # outputs website/dist
make web-deploy    # from the repo root: build + publish to Cloudflare Pages
# Live at https://budgetai-app.pages.dev (privacy: /privacy, deletion: /delete-account)
```

## Android release

Release builds are signed with the upload key at
`/Users/waqas/Muzamil/Keystores/budget-ai.keystore` (alias `budget-ai`). Its
`key.properties` values are backed up beside it in `budget-ai-key.properties.txt`;
`make aab` (or `make apk`) restores the gitignored `android/key.properties`
from that backup when missing and builds with this key; `make verify-signing`
checks it. Losing the keystore or its password blocks
future Play updates, so keep both backed up. Widget preview layouts must not
repeat view ids (release lint fails on duplicates).

Store builds use [Shorebird](https://shorebird.dev) code push (`shorebird.yaml`
holds the public app id):

```sh
make aab            # Shorebird release → upload the AAB to Play (bump version code first)
make patch          # Dart-only fix → live on next app launch, no Play review
make patch-preview  # same, to the staging track (test with: shorebird preview --track=staging)
make aab-flutter    # plain Flutter bundle without code push
```

Native changes (new plugins, Kotlin/Swift, widgets, manifest) require a new
release. Users get store releases through Google Play in-app updates: a
flexible background download with a restart prompt, or an immediate update when
the release's Play update priority is 4–5 (set through the Play Developer API).


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

Finances and Currency use a Cupertino search action that replaces the AppBar title with an unfilled, borderless `Search ...` input. In Finances, search mode keeps the AppBar's back arrow in the leading slot (it closes search) and the summary card collapses with a fade so results get the full height; Currency keeps a non-tappable leading search icon. The close action clears the query and restores normal navigation. Chat History uses the same non-tappable search prefix while searching. Add controls retain their circular primary-color design as floating buttons. The chat composer has a compact 48-pixel minimum height, the standard surface with Material elevation 8, a subtle static border and shadow, and no animated border. The empty chat contains 20 shuffled finance starter prompts, all fully revealed by the end of the entrance animation.

Outgoing chat bubbles occupy at most 86% of the screen width. Their images and captions share a leading edge; multiline text uses natural start alignment while the bubble itself remains on the right. The Finances shortcut paints a transaction list with incoming and outgoing arrows, shared by chat navigation and the Budget Hub Quick Actions card.

Voice requests explicitly send `action: "transcribe"` for compatibility with older speech deployments. Recording/transcription has a leading cancel control; temporary audio is cleaned up on success, cancellation, empty results, and failure. Empty transcripts restore the composer. Explicit chart/image requests are answered with an explanation that image generation is unavailable and an offer of recorded-expense text insights. Deploy both `openai-speech` and `openai-responses` when updating the media contract: stale deployments can reject requests with `invalid_action` or `unsupported_tool`.

Budget Hub → App Behavior → Show Tool Calls toggles inline single/grouped tool rows (on by default, device-local). It changes presentation only; tools still execute and their history is retained. Waiting text occupies the assistant response slot with the same 12-pixel horizontal inset and 16-point/1.5-line-height typography. With tool rows hidden, it remains until response text or an image renders; with rows shown, the first visible tool row replaces it. The two-second label transition retains its original send time when the assistant placeholder is inserted.


Chat image generation and its square shimmer, branded viewer, and image-sharing controls are removed. Camera/gallery input and receipt analysis remain available; existing local image history is preserved. Deploy the updated `openai-responses` function to reject generation requests from older clients too.

## Store screenshots

Final store uploads (Play Console answers, icon, feature graphic, screenshots,
subscription icons) live in `store-listing/`; see its README.

`store-screenshots/` is the App Store and Google Play screenshot editor
(Next.js, scaffolded by the `app-store-screenshots` skill) in the Bento Keynote
Grid style: 8 iPhone slides, 8 Android phone slides and the Play feature
graphic.

```sh
cd store-screenshots
npm install                      # first time only
node scripts/build-deck.mjs      # regenerate app-store-screenshots.json from the deck plan
npm run dev                      # → http://localhost:3000, then Export bundle per device
```

Replace the captures in `public/screenshots/apple/iphone/en/` and
`public/screenshots/android/phone/en/` (same file names) with fresh ones, then
rerun `build-deck.mjs`; it prints where each phone is cropped so crops can be
moved off UI rows. `node scripts/export.cjs <iphone|android|feature-graphic> <dir>`
exports a deck headlessly through the editor's own Export bundle.
The Android phone frame is an original premium bezel (graphite rail, centred
punch-hole camera) drawn by `node scripts/make-android-frame.cjs`; Android
captures are `01.png`–`09.png` (720×1600).

