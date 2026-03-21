# Technology Stack

**Analysis Date:** 2026-03-20

## Languages

**Primary:**
- Swift 5.0 - iOS app (FamilyLife iOS client)
- JavaScript (Node.js) - Backend API server (`dashboard.js`, `database.js`)

**Secondary:**
- SQL - SQLite schema (`schema.sql`)

## Runtime

**Environment:**
- iOS 26+ (deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0`)
- Node.js - Express backend (port 3456 default)

**Package Manager:**
- npm - JavaScript dependencies
- Xcode package management - Swift (no external Swift Package Manager dependencies currently)

## Frameworks

**iOS (SwiftUI/Swift):**
- SwiftUI - UI framework
- SwiftData - Local data persistence and caching
- Swift Concurrency - async/await networking and background tasks
- HealthKit - Health metrics integration (step count, fitness data)
- CoreLocation + MapKit - Location tracking and distance calculations
- UserNotifications - Local push notifications and reminders

**Backend (Node.js/Express):**
- Express 5.2.1 - Web framework and REST API server
- express-session 1.19.0 - Session management for auth
- body-parser 2.2.2 - Request body parsing
- sqlite3 5.1.7 - SQLite database driver
- bcryptjs 3.0.3 - Password hashing (imported but usage unclear from visible code)

**Testing & Build:**
- Xcode 16+ - iOS project build system
- No dedicated test framework configured for backend or iOS

## Key Dependencies

**Critical:**
- sqlite3 5.1.7 - All data persistence, manages `family.db`
- express 5.2.1 - Core REST API, 18+ endpoints for iOS client
- SwiftData - Client-side cache and sync layer for iOS app

**Infrastructure & AI:**
- googleapis 171.4.0 - Google APIs (used in backend, purpose TBD from visible code)
- nodemailer 8.0.1 - Email sending capability (`email-receipts.js`)
- imap-simple 5.1.0 - Email parsing (used in `check-email.js`)
- Anthropic Claude API - Recipe suggestions and receipt scanning via `/api/cook/suggest` and `/api/receipts/scan` endpoints

## Configuration

**Environment:**
- `ANTHROPIC_API_KEY` - Required for AI-powered receipt scanning and recipe suggestions; falls back to mock data if missing
- `PORT` - Express server port (default: 3456)
- `RENDER_DISK_PATH` - Cloud deployment path on Render; otherwise uses `~/.openclaw/workspace/vault/family-life/`
- `server_url` - iOS app stores configured API server URL in UserDefaults; defaults to `http://localhost:3456`

**Auth:**
- Session-based auth via express-session
- Hardcoded user credentials in memory (see `dashboard.js` lines 11-14)
- Cookie-based authentication maintained across iOS app requests

**Build:**
- iOS: Xcode project with bundle ID `com.atlasatlantic.familylife`
- Backend: Node.js server with no build step (plain JavaScript)

## Platform Requirements

**Development:**
- macOS with Xcode 16+
- iOS 26+ device or simulator
- Node.js runtime for backend
- npm for dependency management

**Production:**
- iOS 26+ devices (iPhone/iPad)
- Render hosting (or any Node.js host): Express server, SQLite database storage
- Internet connectivity for API sync between iOS client and backend

## Data Storage & Sync Architecture

**Local (iOS):**
- SwiftData models cached locally in app container: `FLTask`, `Grocery`, `Appointment`, `Receipt`, `PantryItem`, `BudgetCategory`, `Trip`, `Rivalry`, `Decision`, `Gift`, `SpecialEvent`, and related relationship models
- Minimal sync engine required for pull-to-refresh pattern

**Remote (Backend):**
- SQLite `family.db` - Single file at `~/.openclaw/workspace/vault/family-life/family.db` (or Render disk)
- Tables: tasks, groceries, appointments, receipts, pantry, budget_categories, trips, rivalries, decisions, gifts, health metrics, memory/knowledge store
- No transaction management or conflict resolution visible in current schema

---

*Stack analysis: 2026-03-20*
