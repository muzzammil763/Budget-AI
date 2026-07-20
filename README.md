# Budget AI

Budget AI is a Flutter personal finance assistant powered directly by OpenAI, with local finance tracking and JSON backup/restore.

## AI and voice flow

- Chat and finance tools use OpenAI's Responses API.
- The default chat model is `gpt-5.6-luna`. Settings exposes the supported OpenAI model catalog, including GPT-5.6 Sol, Terra, and Luna.
- Chat responses use low reasoning effort and low text verbosity by default, while preserving important amounts, dates, caveats, and next actions.
- Microphone recordings use `gpt-4o-transcribe` through OpenAI's transcription endpoint.
- When the composer is empty, its primary action becomes a hold-to-talk microphone: hold to record and release to transcribe and send. There is no separate microphone button.
- Spoken replies use `gpt-4o-mini-tts`. Settings exposes all 13 built-in voices and defaults to `marin`.
- Voice previews are fixed audio files bundled with the app; replaying them never calls OpenAI or creates API usage.
- A reply is spoken only when its user message was submitted through the microphone. Text-submitted messages remain silent.
- Settings includes a toggle that enables or disables hold-to-talk. The speech and transcription models remain fixed.
- The OpenAI usage screen tracks this installation's response tokens, transcription seconds, speech characters, and successful request counts. It is not a substitute for organization billing data.

## Current app flow

- The app opens directly to chat.
- Tap the app bar model name to open the OpenAI model selector.
- Settings includes finances, insights, currency, OpenAI model, microphone, output voice, local API usage, message style, permissions, backup/restore, and onboarding controls.
- Finance data is stored locally. Backup/restore uses dated JSON files and also accepts compatible finance lists from earlier exports.

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
