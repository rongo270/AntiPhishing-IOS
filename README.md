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
│   ├── ContentView.swift              Dashboard (port of MainActivity) + Safari Protection card
│   ├── LinkCheckView.swift            Checking → result flow for one URL
│   ├── QRScannerView.swift            AVFoundation QR scanner (port of QrScannerActivity)
│   ├── ResultView.swift               Warning screens (port of ResultScreen)
│   ├── Components.swift               SecurityShield, StatCard, RecentLinkItem
│   ├── Theme.swift                    Colors (port of Color.kt)
│   ├── LexicalAnalyzer.swift          ★ Full URL risk engine (port of LexicalAnalyzer.kt)
│   ├── LocalUrlLists.swift            Whitelist/blacklist (port of LocalUrlLists.kt)
│   ├── CheckResult.swift              Result model (port of ApiClient.CheckResult)
│   ├── CheckPipeline.swift            Pipeline coordinator + URL extraction
│   ├── ApiClient.swift                Flask client (port of ApiClient.kt) + /api/stats
│   ├── HistoryStore.swift             Scan history (port of Room DB / LinkDao)
│   ├── AppSettings.swift              Prefs + language (port of SharedPreferences)
│   ├── Localization.swift             EN/HE strings (port of string.xml)
│   ├── URLOpener.swift                Opens confirmed links (app target only)
│   ├── SafariProtectionView.swift     Safari-protection status screen + enable guide
│   ├── AllowlistView.swift            "Approved Domains" management screen
│   ├── AntiPhishing.entitlements      App Group for the app target
│   └── Protection/
│       ├── ThreatFeed.swift           Threat-feed list mirrored from server seed_db.py
│       ├── ProtectionUpdater.swift    Download → validate → atomically activate the DB
│       └── ProtectionCenter.swift     Observable protection state machine for the UI
├── Shared/                            ← compiled into BOTH app and Safari extension
│   ├── SharedStore.swift              THE App-Group storage layer (paths, metadata, flags)
│   ├── ProtectionMetadata.swift       Version/date/counts/hashes of the active DB
│   ├── ProtectionDatabase.swift       SQLite malicious-domain DB (reader + writer)
│   ├── DomainNormalizer.swift         One domain normalization everywhere (incl. punycode)
│   └── AllowlistStore.swift           Shared "Continue Anyway" approvals (24h TTL)
├── AntiPhishingWebExtension/          ← Safari Web Extension target (embedded in the app)
│   ├── SafariWebExtensionHandler.swift  Native handler: local DB lookups, allowlist writes
│   ├── Info.plist / *.entitlements
│   └── Resources/
│       ├── manifest.json              MV3; no host permissions — no network use at all
│       ├── background.js              Verdict pipeline: cache → native checkDomain
│       ├── content.js                 Warning page (Go Back / Continue Anyway)
│       └── popup.html/js/css          Read-only protection status popup
└── ShareExtensionFiles/               ← copy into a Share Extension target (see below)
    ├── ShareViewController.swift
    ├── ShareExtension-Info.plist
    ├── AntiPhishingShare.entitlements
    └── AntiPhishing.entitlements      (legacy copy for the Share-Extension guide)
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
   Default Browser Settings**, which deep-links straight to *Settings ▸ Apps ▸
   Default Apps* using the official iOS 18.3+ API
   (`UIApplication.openDefaultApplicationsSettingsURLString` =
   `app-settings:default-applications`), with a fallback to the app's own
   Settings page. When you return to the app it runs a live check to verify the
   pipeline works and confirms "Protection active". Safe or user-continued
   links open in your chosen default browser.

   > Note: iOS only lets Apple-approved *full browser* apps (with the
   > `com.apple.developer.web-browser` entitlement) be set as the default
   > browser, so AntiPhishing itself won't appear in that list — the screen lets
   > the user pick which browser safe links open in. There is no iOS API to make
   > a non-browser app the system link handler or to detect default-browser
   > status, which is why protection runs through Share/QR/manual instead.

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

## Safari Web Extension protection

The project now ships a **Safari Web Extension** (target `AntiPhishing Web
Extension`, embedded in the app) that checks every page opened in Safari
against a malicious-domain database stored **on the device** — links tapped in
WhatsApp/Mail/Messages that open in Safari are covered automatically.

How it works, end to end:

1. **Database download (app).** The Flask server has no bulk-download
   endpoint — its MongoDB is seeded from public threat feeds
   (`scripts/seed_db.py`, re-run every 12 h). The app therefore downloads the
   same feeds the server seeds from (`Protection/ThreatFeed.swift`) and
   applies the same parsing/normalization rules. `GET /api/stats` supplies the
   server-side domain count used to detect that the server's data moved on.
2. **Storage.** 600k+ domains go into a SQLite file
   (`protection.sqlite`) in the App Group container — exact B-tree lookups, no
   RAM bloat, no Bloom-filter false positives. Per-domain feed source and
   threat category are kept for the warning page.
3. **Updates — button-press only.** Downloads run **solely** when the user
   taps *Download/Update Protection Database* on the Safari Protection
   screen; nothing heavy ever runs implicitly. App launch and
   pull-to-refresh only perform a lightweight `GET /api/stats` (a few
   hundred bytes) to flag *update available*. An update re-checks the feeds
   with conditional GETs (ETag/Last-Modified), rebuilds into a *staging*
   file, validates (min domain count, SQLite integrity check, row count,
   SHA-256), then swaps atomically. A failed update never touches the
   active database.
4. **Extension lookups.** The extension's JavaScript can't read App Group
   files, so `background.js` sends the URL to the native
   `SafariWebExtensionHandler` (`sendNativeMessage`), which normalizes the
   host, consults the shared allowlist, then the SQLite DB (exact host, then
   parent domains). Safe verdicts are cached in `browser.storage.local` for
   12 h, tagged with the DB version so a database update invalidates them.
   **No page URL ever leaves the device from the extension.**
5. **Warning page.** Malicious domains get a full-page AntiPhishing warning
   (domain, threat category, listing feed). *Go Back* is the primary action;
   *Continue Anyway* stores a 24-hour approval in the shared allowlist,
   manageable in the app under **Safari Protection ▸ Approved Domains**.
6. **Offline.** Lookups are 100 % local, so protection keeps working with the
   last downloaded database; the status screen says so explicitly.

**Enabling (manual, required by iOS):** Settings ▸ Apps ▸ Safari ▸
Extensions ▸ AntiPhishing → *Allow Extension* + allow **All Websites**. The
app can only guide you there; it detects activation through a heartbeat the
extension writes on every native call. Note the extension protects **Safari
only** — if Chrome or another browser is your default, links open there
unchecked.

**Verifying it works:**

- Turn on **"Show check confirmation in Safari"** (Safari Protection ▸
  extension card). While it is on the extension bypasses its safe cache, so
  **every page load** runs a live database check and shows a status toast:
  green *"🛡️ example.com checked — safe"*, or an explicit problem state —
  orange *"No protection database — download it in the AntiPhishing app"*,
  gray *"protection is turned off"*, red *"can't reach the app"*. If no
  toast appears at all, the extension itself isn't running: check Settings ▸
  Apps ▸ Safari ▸ Extensions (allow + All Websites) and that the app was
  reinstalled after the extension was added. Turn the toggle off for quiet
  browsing (the cache turns back on).
- Visit a known-bad domain from the database — the full warning page must
  appear.
- **Pull down to refresh** on the home screen or the Safari Protection
  screen: it re-reads the extension heartbeat (e.g. right after enabling the
  extension in Settings), the allowlist, and server freshness — no relaunch
  needed. The *"Safari extension is active / last activity"* row is the
  heartbeat evidence.

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
