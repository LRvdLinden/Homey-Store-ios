# Changelog

## 1.0.1 (build 0.0.6) — 2026-10-15

### Fixed
- **Updating apps works.** The update now sends exactly what my.homey.app sends: the app id, its current channel and the **version** to install (from Homey's own update notice, or the store). Without the version Homey saw the app as already installed and did nothing.
- "Update all" in Mijn Homey uses the same update call.
- Homey Cloud updates its apps by itself (my.homey.app has no update button there either); the app no longer offers an update on Homey Cloud.
- Switching from a test version back to live tries the channel names used by different Homey firmware versions.

## 1.0.1 (build 0.0.5) — 2026-10-15

Full review: all known bugs fixed and a set of new features.

### New
- **Ratings & reviews** on the app page: average, star distribution, review cards with the developer's response, and the full list.
- **More by this developer** on the app page.
- **Works with** now shows the supported devices with product photos and connectivity, plus the app's **widgets**.
- **Install an older version** from the version history (Homey Pro), e.g. to roll back.
- **Filters**: Zigbee, Z-Wave, Matter, Bluetooth, 433 MHz, infrared, Wi-Fi/LAN, cloud and "with widgets", plus sorting by name. New "Op verbinding" section in Apps and Search.
- **Mijn Homey**: updates reported by Homey itself (incl. new permissions), automatic updates on/off, restart app, crashed apps with their message, update badge on the tab, and **your own developer apps** (also test-only).
- **Links**: `homeystore://app/<id>`, pasted homey.app links and app IDs in Search open the app directly; share with icon preview; long-press menu on every app.
- **Search** also finds the apps installed on your Homey.
- **iPad**: sidebar (iOS 18), app cards in columns, readable page widths.
- **Offline banner**; icons retry automatically when the connection returns.
- Homeys where you're not owner or manager are shown as view-only instead of failing afterwards.
- Clear Dutch error messages (offline, time-out, no permission, …); cancelled requests stay silent.
- Haptic feedback when an install succeeds or fails.

### Fixed
- Category lists no longer reset (and lose their scroll position) when going back from an app.
- App icons: real time-out, recovery when iOS stops the hidden renderer, size-limited memory cache, newest icons first, parallel downloads, cancellation when scrolled away.
- Updates and channel switches only report "Installed" once the Homey really runs the new version/channel.
- The install sheet starts on the channel the app runs on (no accidental switch from test to live); "Live" is no longer selectable for test-only apps; an incompatible Homey can't stay selected.
- Signing out of the last account no longer swaps the screen under an open sheet.
- Switching accounts clears everything fetched with the previous account (incl. private/test-only apps).
- An expired login no longer slows down every store request.
- At most 6 store requests at a time and one token request per type, instead of up to 80 at once.
- Update detection uses one shared rule everywhere, checks all installed apps (not just 80) and refreshes on pull-to-refresh.
- Long installs no longer time out after 20 seconds.
- Test versions on the "beta" channel are recognised; colours of private/CLI apps are shown.
- "Nieuw" shows the live release notes, not the test build's.
- Paging: no duplicates or early stop; "Toon alle" also appears when the API gives no total.
- No more "no results" flash while typing in Search.
- Saving accounts can no longer wipe them if the Keychain write fails.
- Long descriptions can always be expanded.
- Store texts and dates follow the app language (no more Dutch/English mix).
- Buttons and texts scale with Dynamic Type.

### Under the hood
- Unit tests for parsing the store and Homey data, update logic and links.
- Removed unused code carried over from Homey Dev.

## 0.0.1 (build 0.0.4) — 2026-10-10

- **App icons fixed:** the store icons (SVG) are now drawn on a canvas — brand colour with the icon as a white mask, exactly like homey.app — and returned as a sharp 3× PNG. Build 0.0.3 showed only the brand colour because the hidden render view was nearly transparent.
- Old, broken icon caches are cleared on first launch.

## 0.0.1 (build 0.0.3) — 2026-10-10

- **Mijn Homeys** now show the real product images, the same as my.homey.app (Homey Pro, Pro mini, Cloud, Self-Hosted Server; light and dark), with the model as subtitle ("Homey Pro (Early 2023)").
- Homey images also in the install sheet, on Mijn Homey and next to the target Homey on the app page.
- App icons load more reliably: rendered on one fixed page, waiting until the SVG is decoded, with retry and timeout; fall back to the app photo.
- Private and CLI-installed apps get the icon served by your Homey.
- App photos and Homey images are cached (memory + disk).

## 0.0.1 (build 0.0.2) — 2026-10-10

- New app icon: frosted triangle, circle and rounded square on the store gradient — no Homey logo.
- New splash screen in the style of the Homey App Store on homey.app; colours follow the chosen store (Homey Pro blue / Homey Cloud pink), with drifting frosted shapes and a curved panel with the store choice.
- Login screen uses the same backdrop; iOS launch screen matches the splash.
- README: screenshots and a Design section.

## 0.0.1 (build 0.0.1) — 2026-10-10

First version.

- Animated splash screen with store preload.
- App Store–style tabs: **Vandaag**, **Apps**, **Mijn Homey**, **Zoeken**.
- Switch between the **Homey Pro** and **Homey Cloud** store.
- App detail page: info strip, What's New, version history, preview, description, works-with, information and links.
- Install on a Homey of your choice, **Live** or **Test** version; update, switch channel, reinstall and remove.
- Test-version banner and section, shareable test link.
- Installed apps per Homey with update detection and "update all".
- Login with Homey or Personal Access Token, multiple accounts with quick switching.
- Light / dark / automatic appearance.
