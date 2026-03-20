# FamilyLife iOS

Native iOS companion app for the Family Life Organizer — a household management system for Jesse and Melissa.

## Overview

FamilyLife brings the full household dashboard to iPhone and iPad: calendar, budget tracking, grocery lists, pantry inventory with receipt scanning, and an AI cooking assistant. It syncs with the existing `family.db` SQLite backend via a lightweight local API.

## Tech Stack

- **SwiftUI** + **SwiftData** (iOS 18+)
- MVVM architecture
- iPhone-first, iPad-compatible
- Bundle ID: `com.atlasatlantic.familylife`

## Getting Started

1. Open `FamilyLife.xcodeproj` in Xcode 16+
2. Select a simulator or device running iOS 18+
3. Build and run

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
├── Models/         # SwiftData models & data types
├── Services/       # API client, sync engine, AI service
└── Resources/      # Assets, colors, fonts
```

## Related

- Web app: `../family-life-organizer/`
- Database: `~/.openclaw/workspace/vault/family-life/family.db`
