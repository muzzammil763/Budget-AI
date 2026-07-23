# Budget AI

Budget AI is a Flutter personal finance assistant using OpenAI for chat, with local finance tracking, offline speech, and JSON backup/restore.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API.
- The default chat model is `gpt-5.6-luna`. Settings exposes the supported OpenAI model catalog, including GPT-5.6 Sol, Terra, and Luna.
- Chat responses use low reasoning effort and low text verbosity by default, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings are transcribed fully on-device with Sherpa-ONNX and a downloaded quantized Whisper model.
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: hold to record and release to transcribe and send. There is no separate microphone button or microphone setting.
- Spoken replies are generated fully on-device with Sherpa-ONNX and a downloaded Piper voice. Audio never leaves the device; only transcribed text is sent to OpenAI for chat.
- Settings > Offline speech models downloads, selects, and removes Whisper STT and Piper TTS models. No speech model is bundled, so voice chat becomes available after one STT model and one TTS model are downloaded.
- Downloaded models select on tap and remove with a left swipe. Downloaded Piper voices also provide locally generated, zero-API-cost audio previews.
- A reply is spoken only when its user message was submitted through the microphone. Text-submitted messages remain silent.
- Paper Curl and Sketch Frame message styles switch the app's default typography to the bundled Patrick Hand font while preserving explicitly branded Boldonse text and monospaced code.

## Current app flow

- The app opens directly to chat.
- Tap the app bar model name to open the OpenAI model selector.
- Settings includes finances, insights, currency, OpenAI chat model, offline speech models, message style, permissions, backup/restore, and onboarding controls.
- Finance data is stored locally. Backup/restore uses dated JSON files and also accepts compatible finance lists from earlier exports.

## iOS widget and Siri entry

- The iOS 17 Home Screen widget is one full-width medium summary with the Budget AI splash mark, current balance, income, spending, and up to two newest entries. Its surface, text, and mark invert with the widget's Light/Dark color scheme. It contains no Siri instructions.
- Say “Add an expense in Budget AI” or “Add income in Budget AI” to Siri. Siri asks for the amount and description, saves the entry without presenting the app, and speaks the confirmation.
- Siri-created entries are written to the shared App Group immediately. A Darwin notification and Flutter method channel import them live when Budget AI is running; launch and foreground imports remain the fallback when iOS has suspended the app.
- Widget data synchronization uses `home_widget` 0.9.3. The WidgetKit UI and App Intents remain native Swift because iOS widgets cannot be rendered as live Flutter views.

Before device testing, create the App Group `group.com.muzamil.budget.ai` in the Apple Developer portal and enable it for both the `Runner` and `BudgetAIWidget` identifiers. App Groups require a paid Apple Developer account. Install and open the app once so iOS can register its App Shortcuts, then add Budget AI from the Home Screen widget gallery. Siri voice entry requires iOS 16 or later; the widget requires iOS 17 or later.

On Android, one wide, non-resizable native Home Screen widget reads the same `home_widget` summary keys and follows the app's Light/Dark styling, including the dynamically inverted Budget mark, without voice instructions. Google Assistant custom App Actions accept one-sentence expense and income commands such as “Hey Google, use Budget AI to log 300 for fuel.” Assistant custom intents require an explicit Budget AI invocation and currently support `en-US`. The action opens Budget AI through a deep link, saves the entry, refreshes the widget and open Finances screen, then confirms through Android text-to-speech and a toast.

## Development

Create a root `.env` file before running or building the app:

```sh
cp .env.example .env
# then set OPENAI_API_KEY in .env
```

```sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
make apk
```

### Regenerating app icons

The launcher icons use a minimal composition of the Budget AI bars, orbit,
dot, and spark, with separate light and dark palettes. After changing the
launcher mark or its brand colours, regenerate the 1024-pixel master plus all
iOS and Android icon variants with:

```sh
flutter test tool/generate_app_icons_test.dart
```

The reusable master PNG is written to
`assets/icons/budget_mark_1024.png`. Android adaptive foreground and
monochrome layers are generated inside the platform resource directories.
Default Android resources use the light icon, while `mipmap-night-*`
alternatives provide the dark icon when the launcher refreshes for the device
night-mode configuration.
iOS and iPadOS receive separate Light, Dark, and Tinted 1024-pixel
appearances, which the system selects from the user's Home Screen appearance.
On Android 13 and later, supported launchers use the monochrome adaptive layer
when the user enables themed icons, tinting it from the wallpaper and system
theme.

The Android native launch screen reuses the adaptive minimal foreground and
the same light/night background colours. Android 12 and later use the platform
SplashScreen attributes, while earlier versions render the matching foreground
from `launch_background.xml` until Flutter draws its first frame.

The mobile app currently calls OpenAI directly, so a packaged API key can be extracted by a determined user. For a public production release, route requests through a small authenticated backend that keeps the OpenAI key server-side.
