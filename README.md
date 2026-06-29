# AntiPhishing — iOS

iOS port of the Android **AntiPhishing** app (by Yahav Eliyahu & Ron Golan).
It identifies phishing links **before** the user opens them and shows a clear,
explained risk verdict. Built with **SwiftUI**.

This is a faithful 1:1 port of the Android app's logic — the full lexical URL
analysis engine, local whitelist/blacklist, warning screens, scan history,
statistics, animated security shield, and English/Hebrew language toggle are
all carried over exactly.

---

## ⚠️ One important iOS platform difference

On **Android**, the app intercepts *every* link tapped in any app by registering
as the system's default browser (browser role + intent filters).

**iOS does not allow this.** Apple does not let any third-party app become the
system-wide link/browser handler or silently intercept links from other apps.
This is enforced at the OS level — there is no legal/App-Store-compliant way
around it. So the iOS version provides the same protection through the
mechanisms Apple **does** allow, which together cover almost the same ground:

| Entry point | How the user triggers it | Android equivalent |
|---|---|---|
| **Share Extension** | In any app (Safari, Messages, WhatsApp, Mail…): **Share → AntiPhishing** on a link | Automatic link interception |
| **QR scanner** | Tap "Scan QR Code" in the app | QR scanner |
| **Manual check** | Paste/type a link on the home screen and tap "Check Link" | — |

Every entry point runs the **same** check pipeline and shows the **same**
warning screens.

---

## Check pipeline (identical to Android)

1. **Step 1 — Backend check:** by default (`IS_LOCAL = false` in
   `CheckPipeline.swift`) the URL is sent to the live Flask backend via
   `ApiClient.swift` — the same `https://antiphishing-backend.onrender.com`
   server the Android app uses. Set `IS_LOCAL = true` for offline development,
   which uses the bundled `LocalUrlLists` whitelist/blacklist instead.
2. **Step 2 — Lexical analysis:** for unknown URLs, the on-device
   `LexicalAnalyzer` runs ~25 checks (length, subdomains, typosquatting,
   homograph/punycode, encoding attacks, suspicious TLDs/keywords, entropy…).
   - If a result is **obviously malicious** (e.g. `@` symbol, `javascript:` URI,
     hidden Unicode, double extension) → blocked immediately.
   - Otherwise → (Step 3 ML server, not built yet) → shown as "needs review".
3. **Result is saved** to the shared scan history and the warning screen is shown.

---

## Project structure

```
AntiPhishing/
├── AntiPhishing/                      ← main app target (auto-synced group)
│   ├── AntiPhishingApp.swift          App entry point
│   ├── ContentView.swift              Dashboard (port of MainActivity)
│   ├── LinkCheckView.swift            Checking → result flow for one URL
│   ├── QRScannerView.swift            AVFoundation QR scanner (port of QrScannerActivity)
│   ├── ResultView.swift               Warning screens (port of ResultScreen)
│   ├── Components.swift               SecurityShield, StatCard, RecentLinkItem
│   ├── Theme.swift                    Colors (port of Color.kt)
│   ├── LexicalAnalyzer.swift          ★ Full URL risk engine (port of LexicalAnalyzer.kt)
│   ├── LocalUrlLists.swift            Whitelist/blacklist (port of LocalUrlLists.kt)
│   ├── CheckResult.swift              Result model (port of ApiClient.CheckResult)
│   ├── CheckPipeline.swift            Pipeline coordinator + URL extraction
│   ├── ApiClient.swift                Flask client (port of ApiClient.kt)
│   ├── HistoryStore.swift             Scan history (port of Room DB / LinkDao)
│   ├── AppSettings.swift              Prefs + language (port of SharedPreferences)
│   ├── Localization.swift            EN/HE strings (port of string.xml)
│   └── URLOpener.swift                Opens confirmed links (app target only)
└── ShareExtensionFiles/               ← copy into a Share Extension target (see below)
    ├── ShareViewController.swift
    ├── ShareExtension-Info.plist
    ├── AntiPhishingShare.entitlements
    └── AntiPhishing.entitlements      (App Group for the MAIN app target)
```

---

## Opening & running

1. Open `AntiPhishing.xcodeproj` in Xcode (26+).
2. Select an iPhone simulator or device and press **Run**. The main app,
   QR scanner, and manual link check work immediately — no extra setup.
   (QR scanning requires a real device or a simulator with a camera; the
   camera-permission string is already configured.)
3. Turning on **Active Protection** shows a short setup screen — the iOS-honest
   equivalent of Android's "grant the browser role" step. It explains how iOS
   checks links (Share → AntiPhishing, QR, manual paste) and offers **Open
   Settings**. When you return to the app it runs a live check to verify the
   pipeline works and confirms "Protection active". Safe or user-continued
   links open in Safari.

### Adding the Share Extension (the "interception" piece)

Adding a new target generates project-file entries that are safest created by
Xcode itself, so the extension is delivered as source you add in three steps:

1. **File ▸ New ▸ Target… ▸ Share Extension** → name it `AntiPhishingShare`.
2. Replace the generated `ShareViewController.swift` with the one in
   `ShareExtensionFiles/`, and use `ShareExtension-Info.plist` as the
   extension's Info.plist (it sets the activation rule for URLs/text).
   Delete the auto-created storyboard if present.
3. Give the extension **Target Membership** of these shared files (select each
   file → File Inspector → tick `AntiPhishingShare`):
   `LexicalAnalyzer, CheckResult, LocalUrlLists, CheckPipeline, ApiClient,
   HistoryStore, AppSettings, Localization, Theme, Components, ResultView,
   LinkCheckView`. (Do **not** add `URLOpener.swift` — it uses
   `UIApplication.shared`, which is unavailable in extensions; the extension
   opens links via its `extensionContext` instead.)
4. Add the **App Groups** capability `group.ronyahav.antiphishing` to **both**
   the app target and the extension (entitlements files are provided). This
   lets them share the same scan history and settings.

After that, "AntiPhishing" appears in the iOS share sheet for any link.

---

## Backend & offline mode

By default the app talks to the live Flask backend
`https://antiphishing-backend.onrender.com` (the same server Android uses).
The endpoints (`/api/check`, `/api/qr/check`, `/api/qr/report`, `/api/score`)
mirror the Android client exactly, and `ApiClient.swift` uses a 60-second
timeout because Render's free tier sleeps when idle and takes ~50s to wake on
the first request.

To work fully offline, set `IS_LOCAL = true` in `CheckPipeline.swift`; the
bundled `LocalUrlLists` whitelist/blacklist is used instead of the server. If
you point `baseURL` at a local `http://` server, add an App Transport Security
exception — iOS blocks plain `http://` by default.

---

## Tests

A unit-test target (`AntiPhishingTests`) covers the ported logic: the
`LexicalAnalyzer` risk engine and its feature vector, the local
whitelist/blacklist, the pipeline's history mapping and URL extraction, the
`HistoryStore` FIFO/dedupe behaviour, and live backend connectivity.

Run them in Xcode with **⌘U**, or from the command line:

```sh
xcodebuild test -scheme AntiPhishing \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The live-network tests live in `ApiClientLiveTests`; skip them for a purely
offline run with
`-skip-testing:AntiPhishingTests/ApiClientLiveTests`.

---

## Credits

Original project by **Yahav Eliyahu** and **Ron Golan**. iOS port preserves the
original algorithm and UX.
```
