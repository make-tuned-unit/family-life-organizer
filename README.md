# Kinrows iOS

Native SwiftUI app and Express/SQLite backend for the Kinrows family organizer.

## Overview

FamilyLife brings the full household dashboard to iPhone and iPad: calendar, budget tracking, grocery lists, pantry inventory with receipt scanning, and an AI cooking assistant. It syncs with the existing `family.db` SQLite backend via a lightweight local API.

## Tech Stack

- **SwiftUI** with Codable API models (iOS 18+)
- MVVM architecture
- iPhone-first, iPad-compatible
- Bundle ID: `com.kinrows.app`

## Getting Started

1. Open `FamilyLife.xcodeproj` in Xcode with the iOS 26 SDK or newer and select the shared **FamilyLife** scheme.
2. For a simulator, select an iOS 18+ destination and use **Product → Build** (⌘B). Debug uses `http://localhost:3456`; start the backend with `npm ci` then `npm start`.
3. For a production device/TestFlight archive, select **Any iOS Device (arm64)** and use **Product → Archive**. The shared scheme archives Release, which uses the production Railway API.
4. Automatic signing uses team `Z58XSBM78S`. The app and widget are both set to version **1.0**, build **243**. Xcode needs your signing account/profiles to create a distributable archive.

For a physical-device Debug run, point the debug server override at your Mac's reachable LAN address; `localhost` on the phone is the phone itself. No QA credentials or simulator launch overrides are stored in the shared scheme.

Backend validation: `npm test`; AI action regressions: `npm run test:ai`; model routing: `npm run test:ai:routing` (live checks require `ANTHROPIC_API_KEY`). See [AI management test coverage](docs/AI_MANAGEMENT_TESTING.md).

## Project Structure

```
FamilyLife/
├── App/            # App entry point, configuration
├── Views/          # SwiftUI views organized by feature
│   ├── Home/       # Dashboard overview
│   ├── Calendar/   # Appointments & scheduling
│   ├── Pantry/     # Pantry inventory & receipt scanning
│   ├── Expenses/   # Budget tracking & receipts
│   └── Cook/       # AI cooking assistant
├── Models/         # Codable models & data types
├── Services/       # API client, auth, calendar sync, widget snapshots
└── Resources/      # Assets, colors, fonts
```

## Related

- Web app: `../family-life-organizer/`
- Database: `~/.openclaw/workspace/vault/family-life/family.db`
