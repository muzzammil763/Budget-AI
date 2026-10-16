# Budget AI — store listing assets

Everything uploaded to Google Play and the App Store lives here. The
screenshots are exported from `store-screenshots/` (the editor and its
sources); this folder holds the final files only.

## Google Play (`google-play/`)

| File | Use |
|---|---|
| `PLAY-CONSOLE-ANSWERS.md` | Copy-paste answers: store listing text, app content, data safety, foreground service, submission checklist |
| `app-icon-512.png` | App icon (512×512) |
| `feature-graphic-1024x500.png` | Feature graphic |
| `screenshots/phone/01.png` … `08.png` | Phone screenshots (1080×1920), upload in order |
| `screenshots/_preview.png` | All eight side by side, for review only |
| `subscription-icons/` | Lite, Plus and Pro subscription icons (1024×1024) |

## App Store (`app-store/`)

`screenshots/iphone-<size>/01.png` … `08.png` at every required iPhone size
(6.9" 1320×2868 is enough on its own; the others are optional). These still use
the older website captures until fresh iOS screenshots are added. The iOS app
also runs on iPad, so App Store Connect will ask for iPad screenshots too.

## Updating

1. Replace captures in `store-screenshots/public/screenshots/...`.
2. `cd store-screenshots && node scripts/build-deck.mjs && npm run dev`.
3. `node scripts/export.cjs <android|iphone|feature-graphic> <dir>`, then copy
   the results here with the same file names.
