# Budget AI Developer Guide

## Architecture

Budget AI is a Flutter application using built-in Flutter state management. Finance data and chat sessions are stored locally.

The AI stack is OpenAI-only:

- `ResponsesProvider` calls `POST https://api.openai.com/v1/responses` for streaming chat and local finance-tool orchestration.
- `OpenAIAudioService` calls `/v1/audio/transcriptions` with `gpt-4o-transcribe` and `/v1/audio/speech` with `gpt-4o-mini-tts`. The selected built-in voice defaults to `marin`.
- `OPENAI_API_KEY` is loaded from the root `.env` asset or a Dart build environment value.
- The model catalog lives in `lib/src/chat/ai_models.dart`; the default is `gpt-5.6-luna`.
- GPT-5 chat requests use low reasoning effort and low text verbosity. Prompts preserve important facts while removing repetition and optional background.
- Speech playback is scoped to microphone-originated turns. Typed messages never trigger automatic audio.
- The composer uses one contextual action: Send when text exists, hold-to-talk when empty and enabled, and Stop during an active response. Releasing a voice hold transcribes and sends immediately.
- Settings exposes a chat-model picker, hold-to-talk toggle, all built-in output voices, bundled zero-API-cost voice previews, and device-local OpenAI usage counters. Speech input/output models are fixed.

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
