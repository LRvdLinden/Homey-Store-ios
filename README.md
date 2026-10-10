<p align="center">
  <img src="HomeyAppStore/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="Homey Store app icon">
</p>

<h1 align="center">Homey Store</h1>

<p align="center">
  The Homey App Store in the look of the iOS App Store — browse apps for Homey Pro and Homey Cloud and install them straight onto your Homey, including test versions.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.0.1%20(0.0.1)-0082FA?style=for-the-badge" alt="Version 0.0.1 build 0.0.1">
  <img src="https://img.shields.io/badge/iOS-17%2B-111111?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/iPadOS-17%2B-111111?style=for-the-badge&logo=apple&logoColor=white" alt="iPadOS 17+">
</p>

---

## What it does

| | |
|:--|:--|
| **Splash screen** | Animated launch (Homey ring on the blue blueprint background) while the store front preloads. |
| **Two stores** | Switch between **Homey Pro** (Pro, Pro mini, Self-Hosted Server) and **Homey Cloud** from the menu top-left — same as the tabs on homey.app/apps. |
| **Vandaag** | Editorial cards like the App Store Today tab: popular, new, just updated, energy, security. |
| **Apps** | Swipeable feature cards, ranked shelves (popular, new, updated, top per category) and all categories. |
| **Zoeken** | Live search with recent searches, suggestions and categories. |
| **App page** | Icon, Install button, info strip (rating, category, developer, version, drivers, Flow cards, SDK), What's New, version history, preview, description, devices it works with, information and links. |
| **Install** | App Store–style sheet: choose the Homey, choose **Live** or **Test**, install — with progress, update / switch-channel / reinstall / remove. |
| **Test versions** | Apps with a test build show an orange banner and a *Testversie* section; install the test or share the test link. |
| **Mijn Homey** | Apps installed on your Homey with available updates (*Werk alles bij*), test installs and CLI dev installs. |
| **Accounts** | Log in like Homey Dev (Homey login or Personal Access Token), multiple saved accounts, quick switching, sign out. |

## How it works

- **Catalogue:** the public Homey App Store API (`apps-api.athom.com/api/v1`): `app/highlight2` (store front), `app/browse` (lists, categories, search), `app/{id}` (details incl. `liveBuild` / `testBuild`), `app/{id}/changelog`.
- **Login:** the same flow as the Homey Dev app — Athom's own login on the Developer Tools website, session kept in the iOS Keychain; or a Personal Access Token.
- **Install:** account token → delegation token (`audience=homey`) → Homey session → `POST /api/manager/apps/store` with `{ id, channel }` (`channel: "test"` for test versions). Remove: `DELETE /api/manager/apps/app/{id}`.
- **Icons:** Homey app icons are SVG; they're rendered once (white on the brand colour, like homey.app) and cached.

## Build

1. Open `HomeyAppStore.xcodeproj` in Xcode 16 or newer.
2. Select your team under *Signing & Capabilities* (bundle id `nl.lrvdlinden.homeyappstore`).
3. Run on an iPhone/iPad or simulator with iOS 17+.

Version **0.0.1**, build **0.0.1** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).

## Notes

- Installing requires an owner/manager role on that Homey.
- Not an official Athom product. App data comes from the public Homey App Store.

© Homey Store – PixelForges
