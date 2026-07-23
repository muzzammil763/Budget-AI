# Supabase Backend and OpenAI Key Security Plan

## Goal

Move every OpenAI API request out of the Flutter application and through an
authenticated Supabase Edge Function. The OpenAI API key will exist only as a
Supabase project secret and will never be bundled into the mobile app.

This migration must preserve:

- OpenAI Responses API streaming.
- Reasoning summaries and response metadata.
- The exact Responses API conversation items needed for tool continuations.
- Local finance tools and local finance storage.
- Cancellation of in-progress responses.
- Chat-title and other utility prompts.

It must also add a polished email/password authentication experience that
appears immediately after first-run onboarding and protects AI chat.

## Target architecture

```text
Budget AI Flutter app
  |
  | Onboarding -> AuthGate -> authenticated app
  |
  | Supabase publishable key + signed-in user's JWT
  | HTTPS request with a validated, limited payload
  v
Supabase Edge Function: openai-responses
  |
  | OPENAI_API_KEY from Supabase Secrets
  | Server-enforced model, payload, quota, and safety rules
  v
OpenAI Responses API
```

MCP is not part of the runtime path. Supabase MCP is an internal development
tool that can help inspect and manage the Supabase project while we build it.
Customers and the released Flutter app must never receive MCP access.

## Decisions and current status

- [x] Create and connect the hosted Supabase project.
- [x] Choose the first authentication method.
  - Required first method: email and password.
  - Require email confirmation before AI chat becomes available.
  - Later additions: Sign in with Apple and Google.
- [x] Select initial limits.
  - Recommended starting point: a conservative daily request limit plus a daily
    token limit, both adjustable without releasing a new app.
  - Keep separate defaults and per-user overrides.
- [x] Select the allowed model IDs from Budget AI's existing model catalog.
- [x] Keep finance data local for the initial backend release; require a
  confirmed account for the current app/chat entry point.
- [ ] Add optional end-to-end encrypted finance synchronization only after the
  recovery-key flow in `OFFLINE_FIRST_SYNC_PLAN.md` is implemented and tested.
- [x] Store operational metadata only—never prompt, response, or finance text.
  Automated retention cleanup remains a rollout follow-up.

## Project setup by the owner

The project owner will:

1. Create the Supabase project in the Supabase dashboard.
2. Keep the database password, service/secret key, access tokens, and OpenAI key
   private.
3. Share only the Supabase project reference ID when it is time to connect MCP.
   The project reference is an identifier, not the OpenAI secret.
4. Configure the chosen Supabase Auth provider and its redirect/deep-link URLs.
   Enable **Confirm email** for email/password registrations.
5. Add `OPENAI_API_KEY` through Edge Function Secrets in the Supabase dashboard.
   Do not paste the key into chat, source code, MCP configuration, or a tracked
   `.env` file.
6. Create a dedicated OpenAI project/API key for Budget AI, configure its
   permissions as narrowly as practical, and set project budget alerts.
7. Rotate the current OpenAI key after the backend is deployed if that key has
   ever been included in a development build.

## Supabase MCP connection

After the project exists, connect the official hosted Supabase MCP server using
browser-based OAuth. A personal access token is normally unnecessary.

Use a project-scoped URL so the connection cannot access unrelated projects:

```text
https://mcp.supabase.com/mcp?project_ref=YOUR_PROJECT_REF
```

Start with a read-only, narrowly scoped connection for discovery:

```text
https://mcp.supabase.com/mcp?project_ref=YOUR_PROJECT_REF&read_only=true&features=database,docs,debugging,functions
```

Read-only mode can inspect the project but cannot apply migrations or deploy an
Edge Function. When implementation begins, temporarily use a project-scoped
write connection with only the feature groups needed for the task. Review each
schema migration and deployment, then return the connection to read-only or
disconnect it.

Supabase recommends MCP for development and testing rather than production
data. For a single free hosted project:

- Develop database changes locally with Supabase CLI where practical.
- Keep real user data out until migrations, RLS, quotas, and the Edge Function
  have passed verification.
- Do not leave broad write-enabled MCP access connected to a live production
  project.
- Never expose the developer MCP connection to app users.

Expected MCP-assisted work:

- Inspect project configuration and database state.
- Apply reviewed SQL migrations.
- Inspect migration history.
- Deploy and inspect Edge Functions.
- Review function and database logs during testing.
- Search current Supabase documentation.

Secret creation remains an owner action through the Supabase dashboard or CLI.
The implementation must not require the OpenAI key to pass through MCP.

## Database design

Create schema migrations rather than making untracked dashboard-only changes.

### `ai_usage_daily`

One row per authenticated user per UTC day:

- `user_id uuid`
- `usage_date date`
- `request_count integer`
- `input_tokens bigint`
- `output_tokens bigint`
- `cached_input_tokens bigint`
- `failed_request_count integer`
- `updated_at timestamptz`
- Primary key: `(user_id, usage_date)`

### `ai_user_limits`

Optional per-user overrides:

- `user_id uuid primary key`
- `enabled boolean`
- `daily_request_limit integer`
- `daily_token_limit bigint`
- `max_concurrent_requests integer`
- `created_at timestamptz`
- `updated_at timestamptz`

If no override exists, the Edge Function uses server-side default limits.

### `ai_request_log`

Minimal operational and abuse-audit metadata:

- `request_id uuid primary key`
- `user_id uuid`
- `client_turn_id uuid`
- `model text`
- `status text`
- `input_tokens bigint`
- `output_tokens bigint`
- `started_at timestamptz`
- `completed_at timestamptz`
- `error_code text`

Do not store prompts, responses, finance data, the OpenAI key, authorization
headers, or raw OpenAI payloads in this table.

### Atomic quota reservation

Use a database function/transaction that atomically:

1. Resolves the user's effective limits.
2. Rejects disabled or over-limit users.
3. prevents excessive concurrent requests.
4. Reserves/increments the request count.
5. Creates the request-log row.

Finalize token totals when the OpenAI stream completes. Count requests that
reach OpenAI even if the client disconnects, because they may still incur cost.

## Row Level Security

- Enable RLS on every application table.
- Users may read only their own usage summary and limits that are safe to show.
- Users must not directly insert, update, or delete usage counters or limits.
- Quota mutations occur only through reviewed server-side functions or the Edge
  Function's server context.
- Never ship a Supabase service-role/secret key in Flutter.
- The Supabase publishable key may be shipped in Flutter because authorization
  is enforced by the user's JWT and RLS policies.

## Edge Function contract

Create one versioned endpoint, initially:

```text
POST /functions/v1/openai-responses
```

The function must:

1. Require and verify a Supabase user JWT.
2. Derive `user_id` from the verified token, never from the request body.
3. Accept only a defined request schema.
4. Reject oversized bodies, conversations, instructions, and tool definitions.
5. Allow only Budget AI model IDs.
6. Force the approved OpenAI endpoint; never accept a target URL from clients.
7. Never accept an API key or arbitrary authorization header from clients.
8. Force approved reasoning, verbosity, streaming, and output-token limits.
9. Allow only Budget AI's known finance-tool schemas when tools are enabled.
10. Reserve quota atomically before contacting OpenAI.
11. Call `https://api.openai.com/v1/responses` with the server-side secret.
12. Proxy the server-sent event stream without buffering the full response.
13. Parse the final usage metadata while forwarding events to the app.
14. Finalize request status and token totals.
15. Propagate cancellation to the upstream request where the runtime permits.
16. Return sanitized errors without secrets or internal stack traces.

The function must not become a generic OpenAI proxy. Authenticated callers
should only be able to perform operations supported by Budget AI.

## Abuse and cost controls

Apply defense in depth:

- Valid Supabase Auth session required.
- Per-user daily request limit.
- Per-user daily token limit.
- Per-user concurrent-request limit.
- Short-window rate limit for bursts.
- Maximum request-body byte size.
- Maximum conversation item count and text length.
- Maximum output tokens set server-side.
- Allowed-model list set server-side.
- Tool name and schema allowlist.
- Duplicate `client_turn_id` protection for accidental retries.
- Timeouts and cancellation.
- OpenAI project budget alerts and usage monitoring.
- Optional temporary user suspension through `ai_user_limits.enabled`.
- Optional device/app attestation in a later hardening phase.

CORS is useful for browser clients but is not an authentication or abuse-control
mechanism and cannot secure a mobile API by itself.

## Flutter migration

### Dependencies and configuration

- Add the official Supabase Flutter client.
- Add only the Supabase project URL and publishable key as public build
  configuration.
- Remove `OPENAI_API_KEY` from Flutter build configuration.
- Remove `.env` from Flutter assets.
- Remove `flutter_dotenv` if it has no remaining purpose.
- Remove startup loading of the bundled `.env`.
- Replace `AppConstants.openAIApiKey` with backend/auth configuration.

### Authentication UX

- Initialize Supabase before chat services.
- Add email/password sign-up, sign-in, email confirmation, forgot-password,
  password-recovery, sign-out, and session restoration.
- Keep local finance features available according to the confirmed product
  decision.
- Show a clear sign-in requirement when AI chat is unavailable.
- Handle expired sessions and refresh tokens without losing the draft message.
- Add sign-out and account/session controls in Settings.

## Authentication navigation and screens

### Root navigation

Replace direct onboarding-to-chat navigation with a root authentication gate:

```text
App launch
  |
  v
Splash
  |
  +-- onboarding not completed --> Onboarding
  |                                  |
  |                                  v
  |                                AuthGate
  |
  +-- onboarding completed -------> AuthGate
                                      |
                                      +-- no session ------> Login
                                      |
                                      +-- recovery event --> Reset Password
                                      |
                                      +-- valid session ---> Chat
```

Specifically:

- `OnboardingScreen._finish()` will still persist completion, but it will
  replace itself with `AuthGate` instead of `UnifiedChatScreen`.
- On later launches, `MyApp` will route through `AuthGate` after the splash.
- `AuthGate` will be driven by one central authentication controller/service
  backed by `supabase.auth.onAuthStateChange`.
- Avoid scattered authentication checks in individual screens.
- During Supabase initialization or token refresh, show a branded transition
  state rather than briefly flashing Login or Chat.
- A signed-out user cannot enter AI chat by navigating back.
- Password-recovery links must override the normal signed-in destination and
  open the Reset Password screen.

### Shared visual system

Create a reusable authentication shell inspired by
`lib/src/onboarding/onboarding_screen.dart`:

- Use the same Google Sans typography, Boldonse branding where appropriate,
  monochrome surfaces, blue accent, rounded 12-pixel controls, responsive
  spacing, and restrained motion.
- Reuse the onboarding visual language without copying its large showcase
  widgets or making authentication slow.
- Provide coordinated page transitions between Login, Register, Verification,
  Forgot Password, and Reset Password.
- Keep forms keyboard-safe, scrollable on compact screens, and usable in both
  Light and Dark modes.
- Respect reduced-motion/accessibility settings.
- Use semantic labels, visible focus states, sufficient contrast, autofill
  hints, correct keyboard types, and screen-reader-friendly validation.
- Disable submit controls only while an operation is active and show progress
  without changing the form's layout.
- Present safe, actionable errors without exposing raw Supabase internals or
  revealing whether an unrelated email address has an account.

### Login screen

Include:

- Email field.
- Password field with show/hide control.
- `Forgot password?` action.
- Primary `Sign in` action.
- Link to `Create account`.
- Inline validation and one consistent error area.
- Email and password autofill support.

Behavior:

- Sign in with `signInWithPassword`.
- On success, allow `AuthGate` to enter Chat.
- If confirmation is still required, route to Email Verification with the
  normalized email and allow resending the signup confirmation.
- Preserve the typed email when moving between auth screens.
- Do not disclose account existence through unnecessarily specific errors.

### Registration screen

Include:

- Display name.
- Email.
- Password.
- Confirm password.
- Password visibility controls.
- Clear password requirements.
- Primary `Create account` action.
- Link back to `Sign in`.

Behavior:

- Normalize the email and validate fields locally before submitting.
- Use Supabase `signUp` with email, password, display-name metadata, and the
  Budget AI confirmation deep-link redirect.
- Supabase Confirm email must remain enabled. A successful registration normally
  returns a user with no session until confirmation.
- Route successful registrations to Email Verification.
- Do not treat an obfuscated existing-user response as proof that an account
  exists; keep the UI response enumeration-safe.

### Email Verification screen

Design this as a polished waiting/status screen rather than a static alert:

- Show the destination email in masked or clearly formatted form.
- Explain that the account must be confirmed before AI chat.
- Provide `Open email app` when supported.
- Provide `Resend email` with a visible cooldown timer.
- Provide `I've confirmed — check again`.
- Provide `Use a different email` and `Back to sign in`.
- Show distinct states for waiting, checking, confirmed, expired/invalid link,
  offline, and resend success/failure.

Verification behavior:

- Support a mobile deep link such as
  `budgetai://auth/confirm` and register the exact redirect URL in Supabase.
- Let `supabase_flutter` process the auth callback.
- Listen to `supabase.auth.onAuthStateChange`; a successful confirmation callback
  should update the screen and let `AuthGate` enter Chat immediately.
- Re-check session state when the app returns to the foreground.
- The manual check action may retry password sign-in using credentials held only
  in memory for the current registration flow; never persist the password.
- Alternatively, configure the confirmation template to include a one-time code
  and allow `verifyOtp` entry. This is a useful fallback for email clients that
  prefetch or break confirmation links.
- Resend with `supabase.auth.resend(type: OtpType.signup, email: ...)`.
- Enforce both the Supabase server cooldown and a matching client countdown.
- Stop listeners/timers when the screen is disposed.

“Realtime” here means reacting immediately to the authenticated deep-link/OTP
callback and auth-state events. Before confirmation there is no valid user
session, so the app must not bypass Supabase security by querying `auth.users`
or repeatedly polling it with administrative credentials.

### Forgot Password screen

Include:

- Email field, prefilled from Login when available.
- Primary `Send reset link` action.
- Neutral success state that does not confirm whether the account exists.
- Resend cooldown.
- Back to Login.

Behavior:

- Call `resetPasswordForEmail` with
  `budgetai://auth/reset-password` as the redirect.
- Register the exact reset redirect in Supabase URL configuration and mobile
  deep-link configuration.
- Keep error copy enumeration-safe.

### Reset Password screen

Open this screen only from a valid `AuthChangeEvent.passwordRecovery` flow:

- New password.
- Confirm new password.
- Password requirement indicator.
- Primary `Update password` action.

Behavior:

- Update through `supabase.auth.updateUser`.
- Clear sensitive controllers and any transient recovery state.
- Show a success transition, then route through `AuthGate`.
- Handle expired or reused recovery links with an action to request a new link.

### Session lifecycle

- Restore the locally persisted Supabase session on launch.
- Treat a locally restored session as provisional if expired.
- Listen for `signedIn`, `signedOut`, `tokenRefreshed`, `userUpdated`,
  `passwordRecovery`, and `userDeleted`.
- Avoid calling the protected Edge Function until a valid session is available.
- Retry an AI request at most once after a successful token refresh; never retry
  non-idempotently without the same `client_turn_id`.
- On sign-out, cancel active AI streams, clear in-memory provider state, and
  return to Login.
- Define separately whether local finance/chat data is retained on sign-out.
  Default recommendation: retain local finance data but clearly explain that it
  remains on the device.

### Email delivery configuration

- Enable Confirm email in Supabase Auth.
- Configure the production Site URL and exact mobile redirect allowlist.
- Customize Confirm signup and Reset password templates with Budget AI wording
  and accessible plain-text fallbacks.
- Do not enable link tracking in the email provider because rewritten links can
  break confirmation.
- Before public release, configure a production SMTP provider and verify SPF,
  DKIM, sender identity, deliverability, expiry, and resend behavior.
- Never place secrets or sensitive user data in email template URLs.

### Chat transport

- Change `ResponsesProvider` to call the Supabase Edge Function.
- Send the Supabase user JWT automatically through the Supabase client or an
  explicitly refreshed session.
- Preserve streaming SSE parsing already used by the app.
- Preserve exact Responses API output items for local tool-call continuation.
- Send a stable `client_turn_id` for retry deduplication.
- Keep local finance-tool execution on the device.
- Route chat titles and utility prompts through the same protected backend.
- Map backend `401`, `403`, `429`, quota, timeout, and upstream errors to clear
  user-facing states.
- Preserve the Stop action by cancelling the Edge Function request.

## Privacy

- Keep finance records and chat sessions local unless a separate sync feature is
  explicitly designed later.
- The Edge Function necessarily receives the conversation sent to OpenAI.
- Do not log prompt/response content by default.
- Do not include local finance data beyond what the user intentionally sends or
  what a local tool result needs for the current OpenAI continuation.
- Document data flow and retention before public release.

## Verification

### Automated tests

- Onboarding completion routes to AuthGate, not directly to Chat.
- Signed-out startup routes to Login without a navigation flash.
- A valid restored session routes to Chat.
- Registration with confirmation enabled routes to Email Verification.
- Registration, login, and recovery errors are enumeration-safe.
- Verification deep links and OTP callbacks create a session and enter Chat.
- Resend confirmation respects its cooldown.
- App resume refreshes the verification/session state.
- Password-recovery links open Reset Password instead of Chat.
- Successful password update returns through AuthGate.
- Sign-out cancels active streams and prevents back navigation into Chat.
- Unauthenticated requests return `401`.
- Invalid/expired JWTs return `401`.
- Users cannot read or mutate another user's usage rows.
- Users cannot modify their own counters directly.
- Model and tool allowlists reject unsupported values.
- Oversized payloads are rejected before an OpenAI call.
- Daily request and token limits return a defined quota error.
- Concurrent and burst limits work atomically.
- Duplicate `client_turn_id` does not double-charge quota.
- Streaming text, reasoning summaries, tool calls, and metadata reach Flutter.
- Tool-call continuations preserve all required Responses API items.
- Cancellation closes the client stream and attempts upstream cancellation.
- OpenAI failures never reveal secrets.
- Request logging contains metadata only.

### Manual tests

- Register using a real email and confirm through the mobile deep link.
- Test confirmation with the app closed, backgrounded, and already open.
- Test resend cooldown, expired links, reused links, and malformed links.
- Test forgot/reset password with the app closed and backgrounded.
- Test keyboard layouts, autofill, compact screens, tablets, Light/Dark mode,
  large text, reduced motion, and screen readers.
- Fresh sign-in and returning-session flows.
- Background/foreground and expired-session recovery.
- Slow and interrupted mobile networks.
- Multiple devices using the same account.
- A complete local finance-tool round trip.
- OpenAI budget and Supabase logs show expected usage.
- The released APK/IPA contains no OpenAI key.
- Direct calls to the Edge Function cannot bypass JWT, quotas, or allowlists.

### Repository checks

```sh
rg "OPENAI_API_KEY|sk-" .
dart format lib test
flutter analyze
flutter test
```

Review every match; documentation placeholders are acceptable, real secrets are
not.

## Rollout order

### Phase 1: Project and connection

- [x] Owner creates the Supabase project.
- [x] Verify hosted Email/password Auth, Confirm email, and redirect URLs in the
  Dashboard.
- [ ] Configure custom SMTP before installing the supplied branded confirmation
  and recovery templates. New free-tier projects cannot customize templates
  while using Supabase's default SMTP; the standard emails still work.
- [x] Connect project-scoped Supabase MCP.
- [x] Inspect the empty project and confirm required capabilities.

### Phase 2: Backend foundation

- [x] Add version-controlled Supabase configuration and migrations.
- [x] Create usage, limits, and request-log tables.
- [x] Enable and inspect RLS, grants, and function privileges.
- [x] Implement atomic quota reservation/finalization.
- [x] Implement and type-check the streaming Edge Function.
- [x] Owner adds `OPENAI_API_KEY` through Supabase Secrets.
- [x] Deploy and verify the authenticated production Edge Function.

### Phase 3: Flutter integration

- [x] Add Supabase initialization and the central AuthGate/service.
- [x] Build the onboarding-inspired shared authentication shell.
- [x] Build Login and Registration.
- [x] Build live Email Verification with deep-link/OTP handling and resend.
- [x] Build Forgot Password and Reset Password.
- [x] Add session restoration, refresh, sign-out, and lifecycle handling.
- [x] Route onboarding completion through AuthGate.
- [x] Replace direct OpenAI requests with Edge Function requests.
- [x] Preserve streaming, tool orchestration, cancellation, and utility prompts.
- [x] Remove the bundled OpenAI key and `.env` dependency.
- [x] Add quota and authentication error states.

### Phase 4: Security verification

- [ ] Run RLS, authorization, quota, replay, concurrency, and payload tests.
- [ ] Inspect the built APK/IPA for secrets.
- [ ] Configure OpenAI budgets and alerts.
- [ ] Rotate the previously bundled key.
- [ ] Confirm logs do not contain sensitive content.

### Phase 5: Controlled release

- [ ] Start with conservative default limits.
- [ ] Monitor errors, latency, token usage, and abuse.
- [ ] Adjust limits from server-side configuration.
- [ ] Return MCP to read-only or disconnect it before real production data.
- [ ] Document incident response and key-rotation steps.

## Rollback

- Keep backend and Flutter changes in separate, reviewable commits.
- Do not restore direct client-side OpenAI access as a production fallback.
- If the backend is unhealthy, show a temporary AI-unavailable state while local
  finance features continue working.
- Roll back the Edge Function deployment or app release independently.
- Rotate the OpenAI key immediately if exposure is suspected.

## Official references

- OpenAI API key safety:
  https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety
- Supabase Edge Functions:
  https://supabase.com/docs/guides/functions
- Supabase Edge Function secrets:
  https://supabase.com/docs/guides/functions/secrets
- Supabase Edge Function authentication:
  https://supabase.com/docs/guides/functions/auth
- Supabase Auth:
  https://supabase.com/docs/guides/auth
- Supabase data security and RLS:
  https://supabase.com/docs/guides/database/secure-data
- Supabase MCP:
  https://supabase.com/docs/guides/ai-tools/mcp
