# Budget AI — Agent Guide

This file is the source of truth for agents working in this repo. Keep it
accurate: **any change that affects what this file describes — the project
structure, features, flows, or architecture — must update this file (and
`README.md`) as part of the same change, before the PR is opened.** A change
that adds/removes/renames files or directories, adds or changes a feature or
screen, or alters a flow or service is not complete until the docs match. If a
change touches nothing the docs describe, no doc update is needed.

Budget AI is a Flutter expense-management assistant: an OpenAI-powered chat that
logs and edits finances through local tools, offline-first SQLite storage with
mandatory end-to-end encrypted Supabase sync, OpenAI voice input and image chat, and native iOS
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
      local_privacy_reset_service.dart  Clears prior-user device data on account exit
      encryption_gate.dart      Mandatory E2E gate: checking → needsSetup → needsRestore → ready
      encryption_setup_screen.dart / encryption_restore_screen.dart
    chat/                       Chat UI + OpenAI Responses streaming + tool loop
      unified_chat_screen.dart  Main chat screen; unified_chat_widgets.dart
      chat_provider*.dart       Streaming client, helpers, tool-call replay
      chat_session_repository.dart  Local-only chat history and images (SQLite)
      chat_image_widgets.dart    Image normalization, attachment previews, zoom viewer
      chat_history_screen.dart, chat_system_prompt.dart, chat_model_config.dart
      active_model_resolver.dart  Resolves active model from Supabase `ai_model_config`,
                                falling back to the default; no in-app picker
      user_bubble_style_surface.dart  Painted user-bubble styles
      chat_response_markdown.dart, markdown_table_view.dart, streaming_text_reveal.dart
    finances/
      finances_screen.dart      List (month/overall pills, AppBar search +
                                floating manual-add button, income/expense totals card); tap → edit
                                screen; no swipe gestures
      finance_entry_edit_screen.dart  Shared create/edit form; AppBar + body save,
                                body delete w/ confirm; auth-style fields;
                                returns FinanceEntryEditResult
      finance_insights_screen.dart    Insights: opens on current month; heatmap clipped
                                to first entry; numberless bars w/ tap-to-reveal popups
      expense_summary_card.dart Shared scoped income/expense card for Finances and Insights
      finance_service.dart      Finance domain logic, actual-expense filtering; legacy rollover recognition
      monthly_summary_service.dart / monthly_summary_card.dart  On-demand monthly AI summaries,
                                cached per account/month in local Shared Preferences
    settings/
      settings_screen.dart      Budget Hub: Quick Actions bento, Account,
                                Preferences, and App Behavior sections
      bubble_style_screen.dart / bubble_style_settings_service.dart
      custom_bubble_style_edit_screen.dart  Colors, shape, pattern, floating preview
      currency_picker_screen.dart / custom_currency_edit_screen.dart
      currency_settings_service.dart / currency_display_card.dart
      ai_usage_service.dart, user_name_settings_service.dart
      ai_usage_sheet.dart          Budget Hub AppBar usage action + details
      admin_service.dart / admin_screen.dart  Role-gated user, quota, AI access,
                                and local-device preference controls
      ai_response_settings_service.dart  Device-local OpenAI Fast mode + tool-row visibility choices
      permission_preferences_service.dart  Soft on/off for notifications + background
    speech/
      openai_speech_service.dart  OpenAI transcription client; no reply playback
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
`analysis_options.yaml`. GitHub Actions runs the Flutter CI workflow for
`master` pushes and pull requests targeting `master`, with cached Flutter and
pub dependencies.

## Architecture

Flutter with built-in state management (no third-party). Finance data is
offline-first in SQLite; the chat backend is OpenAI-only behind Supabase;
speech uses an authenticated Supabase proxy to OpenAI for transcription only.

- `ResponsesProvider` calls the authenticated Supabase `openai-responses` Edge Function for streaming chat and local finance-tool orchestration. The function validates the user JWT, enforces allowlists and per-user quotas, calls `POST https://api.openai.com/v1/responses`, forwards upstream bytes immediately, and finalizes streamed quota usage in a background task. Provider-facing context keeps the current user turn's complete Responses reasoning/function-call/output chain, but compacts completed turns to the 16 most recent user/assistant dialogue items; finance context is fetched on demand through tools instead of attaching an always-on snapshot to every request and tool round. The device-local Fast Responses preference requests `service_tier: "fast"`; the server grants up to the user's monthly Fast allowance (100 by default), then falls back to Standard while retaining overall request/token quotas. Debug timing headers expose quota, OpenAI-header, and region measurements. `SUPABASE_FUNCTION_REGION` is an optional benchmarking override; empty preserves automatic regional routing and failover.
- Administrative authorization lives in `app_user_roles`, not editable user metadata. Missing/null roles are members. Authorized RPCs expose user lists and mutations: admins manage AI access and quota overrides, while only superadmins change roles and a superadmin cannot demote themself. The first superadmin is seeded for `muzamilghafoor2004@icloud.com`.
- `AuthService` uses Supabase email/password auth with required email confirmation, session restoration, OTP verification, password recovery, and sign-out. `AuthGate` shows onboarding/auth, then wraps the chat in `EncryptionGate`.
- `EncryptionGate` makes end-to-end encryption **mandatory**: every authenticated session must generate a key (first device on the account) or restore one (any later device) before reaching the app.
- `AccountEncryptionService` uses AES-256-GCM. The random 256-bit account key is wrapped two ways: by a checksummed `BAI1-…` recovery key, and by a password-derived key (see migration `20260724120000_add_password_wrapped_key.sql`). The device copy is protected by iOS Keychain / Android Keystore. `EncryptedFinanceSyncService` uploads only authenticated ciphertext and uses Realtime plus verified connectivity restoration as invalidation signals. Never upload the recovery key or plaintext finance payload.
- `LocalSettingsStore` stores app settings in SQLite; the retired Shared Preferences import and its migration marker are removed, and database version 2 deletes the obsolete marker from upgraded installs. Account display name, currency, and message bubble style synchronize through `user_settings` via `AccountSettingsSyncService`; custom bubble definitions use the `custom_bubble_styles` JSONB column while `bubble_style` stores the selected preset or `custom:<id>`, so colors, shape, and pattern travel with the account. Onboarding, Fast Responses, and notification/background choices stay local. Permission grants made during onboarding enable the matching local soft preference, and authentication/account sync never replaces it.
- `LocalFinanceStore` imports the legacy finance JSON file into SQLite and tracks revisions, pending writes, and deletion tombstones. Legacy local rows missing from the remote encrypted table are queued automatically. Income appears in the manual Finances list, shared totals, and Home Screen widget; expense charts, tools, and AI summaries remain expense-only. Legacy rollover rows remain stored but hidden. Startup never creates or recalculates rollovers.
- `OpenAiSpeechService` sends PCM16 WAV recordings to the authenticated `openai-speech` Edge Function using `gpt-transcribe` and server-only `OPENAI_API_KEY`. Chat has no automatic or tap-to-play reply audio and no TTS dependency. Empty transcripts show a retry hint. Startup deletes retired `speech_models` artifacts and their selection key.
- Image input uses `image_picker` for camera/gallery, at most three attachments per message, normalized to a 1600-pixel longest edge: PNG up to 384 KB, otherwise metadata-free JPEG compressed in an isolate to at most 768 KB. `ChatMessage.images` and generated `image` blocks persist in local SQLite, never account sync. `chat_image_widgets.dart` owns image normalization, previews, and zoom viewing. Provider context retains only the latest three image inputs while local history keeps older previews. Structured `input_image` parts and active `image_generation_call` items survive tool replay. The chat model receives only finance function tools. The proxy rejects image-generation tools while retaining bounded image inputs. Previously saved image blocks remain viewable in local history. All media passes through authenticated proxies; no public storage uploads.

- `OPENAI_API_KEY` exists only as a Supabase Edge Function secret. Flutter contains only the Supabase URL and publishable key; `.env` is not an app asset.
- The default model and allowed model IDs live in `lib/src/chat/active_model_resolver.dart`; the default is `gpt-5.6-luna`. There is no in-app model picker — `ActiveModelResolver` reads a single global override row from the Supabase `ai_model_config` table (falling back to the default on any missing/invalid/error case) so the model can be changed from the backend without an app update; see README "Changing the active AI model". OpenAI chat requests use explicit `top_p: 1.0` sampling. GPT-5 chat reasoning routes conservatively per prompt: exact greetings/thanks use `none`, clear analytical signals use `medium`, and all other prompts default to `low`; utility prompts remain `low`. GPT-5 requests use low text verbosity. Prompts preserve important facts while removing repetition.
- `finance_summary` returns actual expense totals and categories only for every date range, excluding income and internal transfers.
- Finance tools (`lib/src/tools/`, registered in `tools.dart`): `finance_add`, `finance_list`, `finance_summary`, `finance_update`, `finance_delete`.

## Feature surface

Chat pre-warms the temporary recording path and already-granted microphone status without activating capture. Hold-to-talk begins on pointer-down instead of waiting for Flutter's long-press timeout; startup feedback stays within the mic button, the composer changes only after capture begins, and releasing while startup is still in flight cancels safely. During active responses, the conversation immediately shows `Thinking ...`, smoothly changing to `Budget AI is working ...` after two seconds until visible response content, or the first tool call when tool rows are enabled. The bottom composer retains its working status and Stop action in 16-point Google Sans typography. The composer activity mark contains only animated bars, with no surrounding circle.

Chat top chrome provides History and New Chat on the left and Finances (painted transaction-list mark), Insights (Budget mark), and Budget Hub on the right. New Chat uses the existing fresh-draft flow and active-response guard. Budget Hub navigation opens immediately from cached state while admin and usage refreshes continue in the background.

- **Chat** — streaming OpenAI chat that logs/queries finances via tools. Tool calls are visible by default and can be hidden with the device-local Show Tool Calls preference in Budget Hub. When enabled, they appear inline in chronological order: single calls show expandable status rows, consecutive calls use expandable grouped summaries, and details expose arguments/results. Hold-to-talk uses OpenAI transcription; all chat replies stay silent. Camera/gallery inputs can be analyzed as receipts and expenses; finance tools log requested entries, with clarification for unreadable details and no double-counting receipt totals. Image generation is unavailable; spending-pattern requests receive text insights or tables. The top-right chrome contains equal-size Finances (painted transaction-list mark), Insights (Budget mark), and Budget Hub actions; New Chat sits beside History on the left. Entering Chat preloads monthly AI usage, the account's admin role, and the authorized admin user list; Settings opens immediately from cached state while refreshes continue in the background. The normal composer has a + prefix opening a compact elevated Camera/Photos panel with direct icons and content-sized width, up to three removable and zoomable previews, and up to four text lines without a separate expanded editor. Its inactive empty/single-line state is fully pill-shaped; wrapped text or attachments use 28-radius corners and move actions below the text. Its contextual trailing action is Send when text or images exist, hold-to-talk when empty, and Stop during a response. A leading Cancel action is available during recording and transcription; cancelled or superseded voice results cannot auto-send. Completed-response notifications convert the complete Markdown response to readable plain text and use Android's expandable large-text style; the OS controls collapsed and lock-screen visibility. Leaving the foreground during an active response skips the buffered typewriter reveal, requests the limited iOS background-execution window, and schedules notification delivery before releasing it; iOS can still suspend unusually long work. Markdown tables left-align every header and value column. The model is not user-facing anywhere in the UI. Chat history is local-only. All styles use the bundled Google Sans font; Boldonse branding and monospaced code are preserved.
- **Finances** — month/Overall scopes list expenses and income, including existing income, with red expense and green income amounts. Manual create/edit offers an Expense/Income selector. The shared card shows separate totals with red outgoing and green incoming icons and normal card-colored amounts. Search and manual create/edit/delete support both types. Balances, Saved/Overused, and rollovers stay absent; legacy rollover records remain stored but hidden.
- **Insights** — selected/current-month spending, Overall spending, expense categories, heatmaps, daily trends, and highlights. The shared summary includes income totals; net/savings cards remain removed. Each nonempty expense month ends with an on-demand Monthly Summary; Generate/Regenerate sends only actual expense totals, categories, and daily spending through the authenticated OpenAI utility endpoint. Account/month Shared Preferences caches use a new expense-summary namespace so old income summaries are not displayed; they never sync and clear on account exit. In-flight requests cannot restore data after account exit.
- **Administration** — Budget Hub's AppBar owns the preloaded monthly AI-usage indicator and details sheet. Admins and superadmins see role-gated controls for user listing, search, current-month request/token progress, AI blocking, per-user request/token/Fast overrides, and a dedicated local-preferences screen with confirmed deletion. The screen and editor use the same AppBars, 12-radius bordered cards, auth-style fields, app buttons, and responsive sheets as the rest of Budget AI. Only superadmins can assign Member/Admin/Super Admin roles, and they cannot demote themselves.
- **Budget Hub** — sectioned landing screen with bento-style Finances and Insights Quick Actions, inline Account controls for editing the name, viewing the read-only email, and password recovery, Preferences for Currency display and Message bubble, plus Show Tool Calls, Fast Responses, Notifications, Android Background Service, and Replay onboarding controls under App Behavior. Its AppBar shows the preloaded monthly AI-usage action. Fast Responses is off by default, stays device-local, and opts chat/tool/utility requests into OpenAI Fast mode with a disclosed per-token pricing premium. Notifications strictly gates delivery; disabling it also clears existing app notifications. Replay onboarding pushes the same five-page flow with a top Back action; Back and final completion both return to Budget Hub instead of replacing the route with auth. Sign out and permanent account deletion sit at the end in a dedicated Danger Zone; deletion runs through an authenticated Edge Function and account-owned cloud rows cascade with the auth user. The currency picker is also available during onboarding before sign-in; preset selection and custom currency creation persist locally for the later account flow. It uses borderless AppBar search with a circular floating add action that opens a dedicated custom-currency add/edit form; custom displays are limited to five characters and saved custom entries expose edit/delete actions. It reveals the selected display on entry, jumps directly to newly saved custom displays without a visible scroll animation, and remains open after selection until the user navigates back. The bubble-style picker has no search or custom-add action; its second preset is Outline, using the Primary shape with a transparent fill and primary-color border. Existing custom styles retain edit/delete actions, and its custom editor supports named bubble/text/pattern colors, rounded/chat/pill/angular/ticket shapes, none/dots/diagonal/grid/waves patterns, and a top-floating live preview that remains visible while controls scroll. Encryption is not a setting — it is handled by the mandatory gate.
- **Native entry points** — iOS 17 Home Screen widget + Siri App Intents ("Add an expense in Budget AI"); Android Home Screen widget + Google Assistant App Actions. Both write to the shared store and import live via Darwin notification / method channel. The native square widget shows compact income and expense cards with a corner control for browsing synced months and no future-month navigation. The iOS system-small family uses a single reference-matched soft-3D scene (sprout mascot, calendar, sign, dimensional cards/icons, footer, and landscape) with native live text precisely overlaid in reserved areas. Income shortcuts are retired. See README for App Group and setup details.

## Development rules

- Use `StatefulWidget`, `ValueNotifier`, `ChangeNotifier`, `FutureBuilder`, or `StreamBuilder`; do not add third-party state management.
- Keep provider-specific request shapes isolated in their service/provider files.
- Preserve Responses API reasoning, function-call, function-call-output, and message items while replaying the active tool turn. Completed turns may discard internal items only after their final assistant message represents the outcome.
- Update `README.md` and this file when setup, models, API surfaces, voice behavior, structure, or features change.
- Never commit `.env`, an OpenAI key, a Supabase secret/service-role key, or a Supabase access token. All OpenAI traffic must remain behind the authenticated Edge Function.
- Never claim a lost recovery key can be recovered. Chat history must remain excluded from Supabase synchronization. Never expose the OpenAI credential in Flutter.

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

Finances and Insights share `expense_summary_card.dart`: the same rounded gradient card shows separate scoped expense and income totals, expense entry count, distinct expense days, and daily expense average. Income-only and empty scopes also show both totals. Daily average covers calendar days from the first scoped expense through today (or the last day of a past month); empty scopes show zero. Search filters the list without changing the scope summary.

Image input uses Responses `input_image` parts with base64 data URLs, as documented at https://developers.openai.com/api/docs/guides/images-vision. Chat allows 90 seconds before the first visible image-analysis content, including retries with existing image context; inactivity timeout cancels HTTP before awaiting stream cleanup. Attachment strips use their content width with 64-pixel composer and 72-pixel message previews, retaining removal and zoom. The shared spending card displays explicit Overall dates and a 1–today range for the current month.

Attachment composer rows align left, with up to three previews side by side; user text uses natural start alignment beneath image previews, sharing their leading edge inside a right-positioned bubble. Small screenshots stay PNG; larger decoded images become metadata-free JPEGs capped at 768 KB using the `image` package in a background isolate, avoiding photo-to-PNG payload inflation.

Request failures include sanitized JSON diagnostics: payload size, attachment MIME/encoded size, uploaded bytes, last confirmed proxy/response stage, and elapsed time. Inactivity timeouts surface immediately instead of silently retrying; stream cleanup is bounded to two seconds. Diagnostics never include prompts, image bytes, or credentials and do not assume OpenAI received an image before response events are observed.

Only explicit Stop actions display Request Cancelled. Internal cancellations retain an interruption message and request diagnostics; cancellation-cleanup exceptions cannot mask the original failure.

Finances and Currency use a Cupertino search action that replaces the AppBar title with an unfilled, borderless `Search ...` input. Search mode has a non-tappable leading search icon; its close action clears the query and restores normal navigation. Chat History uses the same non-tappable search prefix while searching. Add controls retain their circular primary-color design as floating buttons. The chat composer has a compact 48-pixel minimum height, the standard surface with Material elevation 8, a subtle static border and shadow, and no animated border. The empty chat contains 20 shuffled finance starter prompts, all fully revealed by the end of the entrance animation.

Outgoing chat bubbles occupy at most 86% of the screen width. Their images and captions share a leading edge; multiline text uses natural start alignment while the bubble itself remains on the right. The Finances shortcut paints a transaction list with incoming and outgoing arrows, shared by chat navigation and the Budget Hub Quick Actions card.

Voice requests explicitly send `action: "transcribe"` for compatibility with older speech deployments. Recording/transcription has a leading cancel control; temporary audio is cleaned up on success, cancellation, empty results, and failure. Empty transcripts restore the composer. Explicit chart/image requests are answered with an explanation that image generation is unavailable and an offer of recorded-expense text insights. Deploy both `openai-speech` and `openai-responses` when updating the media contract: stale deployments can reject requests with `invalid_action` or `unsupported_tool`.

Budget Hub → App Behavior → Show Tool Calls toggles inline single/grouped tool rows (on by default, device-local). It changes presentation only; tools still execute and their history is retained. Waiting text occupies the assistant response slot with the same 12-pixel horizontal inset and 16-point/1.5-line-height typography. With tool rows hidden, it remains until response text or an image renders; with rows shown, the first visible tool row replaces it. The two-second label transition retains its original send time when the assistant placeholder is inserted.


Chat image generation and its square shimmer, branded viewer, and image-sharing controls are removed. Camera/gallery input and receipt analysis remain available; existing local image history is preserved. Deploy the updated `openai-responses` function to reject generation requests from older clients too.
