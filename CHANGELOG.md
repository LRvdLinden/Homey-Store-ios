# Changelog

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
