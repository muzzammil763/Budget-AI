Bundled OpenAI voice preview clips live here as `<voice-id>.mp3`.

The app only plays these files for previews. It never calls the OpenAI Speech
API from the voice picker, so replaying a preview cannot create API charges.

The 13 clips were generated once on 2026-07-20 with `gpt-4o-mini-tts`. They
use the same short introduction and neutral speaking instructions so voices
can be compared consistently. Do not regenerate them at runtime.
