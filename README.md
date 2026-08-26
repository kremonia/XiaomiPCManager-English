# Xiaomi PC Manager — English UI Patch

![Target version](https://img.shields.io/badge/target_version-5.8.1.121-blue)
![Platform](https://img.shields.io/badge/platform-Windows_10%2F11-0078D6)
![License](https://img.shields.io/badge/license-MIT-green)

An unofficial English translation patch for **小米电脑管家 (Xiaomi PC Manager)** — Xiaomi's PC companion app for its laptops, tablets and phones.

The Chinese-market build contains **no English resources at all**: it ignores the Windows display language, exposes no language setting, and there is no international build to download. This patch swaps the app's Chinese UI text for English by replacing the strings inside its web-based UI bundles.

## What gets translated

| Area | Status |
|---|---|
| Home / device dashboard | ✅ English |
| Device interconnect (HyperConnect) | ✅ English |
| Toolbox (cleanup, battery, performance…) | ✅ English |
| Settings | ✅ English |
| Driver management | ✅ English |
| Feedback | ✅ English |
| AI Search overlay (file search) | ✅ English |
| Tray icon menu & some native popups | ❌ still Chinese — compiled into native DLLs |
| Privacy agreement & legal texts | ❌ still Chinese |
| Province/city picker | ❌ still Chinese (China-only region services) |
| Update/version-check windows (native shell) | ❌ still Chinese |

About **2,400 strings** across the two UI bundles: ~1,950 in the main window and ~460 in the AI Search overlay.

## Requirements

- Windows 10 / 11
- Xiaomi PC Manager **5.8.1.121** installed from the China installer
  (`OvRa_XiaomiPCManager_feature_p52_5.8.1.121_*.exe`)
- Administrator rights (the app lives under `C:\Program Files\MI\`)

## Install

1. Clone or download this repository.
2. Double-click **`INSTALL-ENGLISH.bat`** and accept the UAC prompt.
3. The script closes the app, backs up the original files as `*.zh-CN.bak`, copies the English bundles in, and restarts the app.

That's it — the main window, settings, toolbox, drivers, feedback and AI Search are now in English.

## Roll back

Double-click **`RESTORE-CHINESE.bat`**. The originals are restored from the `.zh-CN.bak` backups and the app restarts.

## How it works

Xiaomi PC Manager is a WinUI 3 shell whose screens (main window, settings, toolbox, drivers, feedback, AI Search) are rendered in **WebView2** — they are web pages. All visible Chinese text lives in two JavaScript bundles:

| Bundle | UI | Strings |
|---|---|---|
| `dist/static/js/main.js` | Main window | ~1,950 |
| `Search/dist/assets/index.js` (+ `index-legacy.js`) | AI Search overlay | ~460 |

The patch replaces every Chinese string with its English equivalent **in place** — no code logic is touched. `translations.json` holds the full Chinese→English dictionary (1,283 entries), so the patch can be regenerated against future versions.

### After an app update

The updater installs a fresh version folder with Chinese files, which overwrites the patch. The `.bat` scripts always target the newest version folder, but the patched bundles were built from 5.8.1.121 — after an update some strings may fall back to Chinese. To re-translate:

1. Copy the fresh Chinese bundles out of the new install folder.
2. Apply `translations.json` to them (replace each Chinese key with its English value).
3. Copy the results back into this repo's `dist/` and `Search/` folders and re-run the installer.

> ⚠️ **Only translate actual CJK text.** Some innocuous-looking characters in the bundles (e.g. `￿`, U+FFFF) are endpoints of character ranges inside regular expressions — replacing them corrupts the bundle, and the app hangs on a loading spinner at startup.

## Project structure

```text
.
├── INSTALL-ENGLISH.bat      # install the English UI (self-elevating)
├── RESTORE-CHINESE.bat      # one-click rollback
├── translations.json        # full Chinese→English dictionary (1,283 entries)
├── dist/
│   └── static/js/main.js    # patched main-window bundle
└── Search/
    └── dist/assets/         # patched AI Search bundles
        ├── index.js
        └── index-legacy.js
```

## Disclaimer

This is an unofficial fan translation. It is not affiliated with, endorsed by, or supported by Xiaomi. "Xiaomi", 小米电脑管家 and related trademarks belong to Xiaomi Inc. Use at your own risk — the installer backs up every original file it touches, and `RESTORE-CHINESE.bat` undoes the patch at any time.

## License

Released under the [MIT License](LICENSE).

The MIT license covers the original work in this repository: the translation dictionary, the batch scripts, and the documentation. The patched JavaScript bundles are derived from Xiaomi's proprietary code, remain the property of their respective owners, and are included here solely as a functional patch for existing installations of the app.
