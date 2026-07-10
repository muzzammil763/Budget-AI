# Budget AI

Budget AI is a Flutter personal finance assistant with DeepSeek chat, local expense tracking, and JSON backup/restore.

## Current App Flow

- The main screen opens directly to chat.
- Tap the chat app bar title area showing `Budget AI` and the current model name to open the model selector.
- Settings contains three options: API Keys, Finances, and Backup & Restore.
- API Keys supports multiple saved DeepSeek keys.
- Backup & Restore exports and imports API keys, finances, and the selected DeepSeek model.
- Restore also accepts OpenGate finance exports/backups that contain a `finances` list.
- Backup files use a dated name like `Backup Budget AI 12-12-2026 12 35 PM.json`.

## Development

Create a root `.env` file before running or building the app:

```sh
cp .env.example .env
# then set DEEPSEEK_API_KEY in .env
```

```sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
make apk
```

There is currently no `test/` directory in this app.
