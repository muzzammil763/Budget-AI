# Budget AI Developer Guide

## Architecture

Budget AI is a Flutter application using built-in Flutter state management. Finance data and chat sessions are stored locally.

The chat stack is OpenAI-only, while speech is local:

- `ResponsesProvider` calls `POST https://api.openai.com/v1/responses` for streaming chat and local finance-tool orchestration.
- `LocalSpeechService` uses Sherpa-ONNX for on-device Whisper transcription and Piper speech synthesis. `LocalSpeechModelManager` downloads, selects, persists, and removes model archives from application support storage.
- `OPENAI_API_KEY` is loaded from the root `.env` asset or a Dart build environment value.
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
- Never commit `.env` or an API key. A public production release should proxy OpenAI requests through an authenticated backend instead of shipping the key in the app.

## Verification

```sh
dart format lib test
flutter analyze
flutter test
```
