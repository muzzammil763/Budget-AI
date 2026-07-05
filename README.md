# Budget AI

Budget AI is a Flutter personal finance assistant with DeepSeek chat, local expense tracking, saved memories, web-search support, and JSON backup/restore.

## Current App Flow

- The main screen opens directly to chat.
- Tap the chat app bar title area showing `Budget AI` and the current model name to open the model selector.
- Settings contains four options: API Keys, Finances, Memories, and Backup & Restore.
- API Keys supports multiple saved DeepSeek and SearchAPI keys.
- Backup & Restore exports and imports API keys, finances, memories, and the selected DeepSeek model.
- Backup files use a dated name like `Backup Budget AI 12-12-2026 12 35 PM.json`.

## Development

```sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
```

There is currently no `test/` directory in this app.
