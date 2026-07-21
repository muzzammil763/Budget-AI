# Budget AI

Budget AI is a Flutter personal finance assistant powered directly by OpenAI, with local finance tracking and JSON backup/restore.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API.
- The default chat model is `gpt-5.6-luna`. Settings exposes the supported OpenAI model catalog, including GPT-5.6 Sol, Terra, and Luna.
- Chat responses use low reasoning effort and low text verbosity by default, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings use `gpt-4o-transcribe` through OpenAI's transcription endpoint.
- When the composer is empty, its always-available primary action becomes a hold-to-talk microphone: hold to record and release to transcribe and send. There is no separate microphone button or microphone setting.
- Spoken replies use `gpt-4o-mini-tts`. Settings exposes all 13 built-in voices and defaults to `marin`.
- Voice previews are fixed audio files bundled with the app; replaying them never calls OpenAI or creates API usage.
- A reply is spoken only when its user message was submitted through the microphone. Text-submitted messages remain silent.
- Paper Curl and Sketch Frame message styles switch the app's default typography to the bundled Patrick Hand font while preserving explicitly branded Boldonse text and monospaced code.

## Current app flow

- The app opens directly to chat.
- Tap the app bar model name to open the OpenAI model selector.
- Settings includes finances, insights, currency, OpenAI model, output voice, message style, permissions, backup/restore, and onboarding controls.
- Finance data is stored locally. Backup/restore uses dated JSON files and also accepts compatible finance lists from earlier exports.

## iOS widget and Siri entry

- The iOS 17 Home Screen widget is one full-width medium summary with the Budget AI splash mark, current balance, income, spending, and up to two newest entries. It contains no Siri instructions.
- Say “Add an expense in Budget AI” or “Add income in Budget AI” to Siri. Siri asks for the amount and description, saves the entry without presenting the app, and speaks the confirmation.
- Siri-created entries are written to the shared App Group immediately. A Darwin notification and Flutter method channel import them live when Budget AI is running; launch and foreground imports remain the fallback when iOS has suspended the app.
- Widget data synchronization uses `home_widget` 0.9.3. The WidgetKit UI and App Intents remain native Swift because iOS widgets cannot be rendered as live Flutter views.

Before device testing, create the App Group `group.com.muzamil.budget.ai` in the Apple Developer portal and enable it for both the `Runner` and `BudgetAIWidget` identifiers. App Groups require a paid Apple Developer account. Install and open the app once so iOS can register its App Shortcuts, then add Budget AI from the Home Screen widget gallery. Siri voice entry requires iOS 16 or later; the widget requires iOS 17 or later.

On Android, one wide, non-resizable native Home Screen widget reads the same `home_widget` summary keys and follows the app's styling without voice instructions. Google Assistant custom App Actions accept one-sentence expense and income commands such as “Hey Google, use Budget AI to log 300 for fuel.” Assistant custom intents require an explicit Budget AI invocation and currently support `en-US`. The action opens Budget AI through a deep link, saves the entry, refreshes the widget and open Finances screen, then confirms through Android text-to-speech and a toast.

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

The mobile app currently calls OpenAI directly, so a packaged API key can be extracted by a determined user. For a public production release, route requests through a small authenticated backend that keeps the OpenAI key server-side.
