# External Integrations

**Analysis Date:** 2026-03-20

## APIs & External Services

**Anthropic Claude API:**
- Receipt scanning and OCR for expense tracking (`/api/receipts/scan`)
  - SDK/Client: Direct fetch to `https://api.anthropic.com/v1/messages`
  - Auth: `ANTHROPIC_API_KEY` env var (required, mocked if missing)
  - Model: claude-sonnet-4-20250514
  - Max tokens: 1500

- Recipe suggestion engine for Cook feature (`/api/cook/suggest`)
  - Same Claude API integration
  - Max tokens: 2000
  - Prompts for ingredient-based recipe generation

**Google APIs:**
- googleapis 171.4.0 dependency listed in package.json
  - Purpose not visible in current code; likely for calendar or email integration
  - Requires Google API credentials setup (not yet configured)

## Data Storage

**Databases:**
- SQLite (`family.db`)
  - Connection: Local file at `~/.openclaw/workspace/vault/family-life/family.db` (or `/opt/render/project/src/vault/family-life/family.db` on Render)
  - Client: sqlite3 npm package (Node.js) + raw SQL queries
  - No ORM used; queries built directly in `database.js`
  - Single database file shared between web and iOS clients
  - Tables:
    - Core: `tasks`, `groceries`, `appointments`, `receipts`, `pantry`, `budget_categories`
    - Features: `trips`, `rivalries`, `decisions`, `gifts`, `health`
    - System: `memory`, `automations`, `users`

**File Storage:**
- Local filesystem only - No S3, cloud storage, or CDN
- Receipt images encoded as base64 before sending to Anthropic API
- No persistent file storage for receipt scans

**Caching:**
- SwiftData local cache (iOS only) - Not synced to backend
- No Redis, Memcached, or server-side caching

## Authentication & Identity

**Auth Provider:**
- Custom/In-app - No OAuth, Auth0, or third-party IdP
  - Implementation: express-session + hardcoded user credentials
  - Users stored in-memory in `dashboard.js` (lines 11-14):
    - `jesse` / `lauft2024`
    - `sophie` / `family2024`
  - Passwords plaintext in config (not hashed at login)
  - iOS: Credentials persisted to UserDefaults after login
  - Web: Session cookies maintained across requests

**Session Management:**
- express-session with in-memory store
- HTTP cookies (not secure flag in dev; `{ secure: false }`)
- iOS app maintains cookies via URLSession configuration (`httpCookieStorage = .shared`)

## Monitoring & Observability

**Error Tracking:**
- None detected - No Sentry, DataDog, or similar

**Logs:**
- console.log in backend (visible in server output)
- iOS: No centralized logging framework
- No log aggregation or persistence

## CI/CD & Deployment

**Hosting:**
- Render.com - For Node.js Express backend (uses `RENDER_DISK_PATH` for persistent storage)
- Local network - iOS development/testing (`http://localhost:3456`)
- No iOS app distribution (no TestFlight, App Store setup visible)

**CI Pipeline:**
- None detected - No GitHub Actions, GitLab CI, or similar

**Build & Deploy:**
- iOS: Manual via Xcode (no automated builds)
- Backend: Deploy via Render git integration (git push triggers rebuild)

## Email & Communication

**Email Provider:**
- Nodemailer 8.0.1 - For sending emails
  - Implementation: `email-receipts.js` likely uses SMTP transport
  - Credentials required in env vars (exact transport config not visible)

**Email Parsing:**
- imap-simple 5.1.0 - For receiving and parsing emails
  - Implementation: `check-email.js` monitors inbox
  - Likely used for receipt email extraction before OCR
  - Requires IMAP server credentials

## Webhooks & Callbacks

**Incoming:**
- None visible - API is REST-only, no webhook receiver endpoints

**Outgoing:**
- None visible - No webhooks sent to external services

## External Data Sources

**Health Data (iOS):**
- HealthKit read-only access - Fetch step count and fitness metrics
  - `HealthKitManager.swift` - Requests authorization for step data
  - Stored locally in SwiftData; sent to backend via `/api/health` (endpoint TBD)

**Location Data (iOS):**
- CoreLocation - Real-time device location for trip tracking
  - `LocationService.swift` - Requests when-in-use permission
  - Used for ETA calculations and arrival notifications
  - Data stays on device; optional sync to backend

## Environment Configuration

**Required env vars:**
- `ANTHROPIC_API_KEY` - Claude API key (no fallback; receipts/recipes fail gracefully)
- `PORT` - Server port (optional, default 3456)
- `RENDER_DISK_PATH` - Cloud deployment flag (auto-detected by Render)

**Optional env vars (inferred from dependencies):**
- `GOOGLE_API_KEY` or similar - For googleapis integration (not yet active)
- SMTP credentials for nodemailer transport
- IMAP credentials for email parsing

**Secrets location:**
- `.env` file expected (not checked into repo)
- Server config hardcodes demo user passwords (security risk)
- No .env.example or documented required vars

## Data Sync Architecture

**iOS ↔ Backend:**
- Pull-based: `APIService` makes explicit GET/POST requests
- No real-time sync or websockets
- No offline queue or conflict resolution
- Manual refresh required for new data from backend
- Cookie-based session carries auth state across requests

**Receipt Workflow:**
1. iOS: User scans receipt image → base64 encode
2. POST `/api/receipts/scan` with image data
3. Backend: Send to Anthropic Claude → parse items, total, merchant, date
4. Return structured `ScanResult` to iOS
5. iOS: Display for review → User confirms → POST `/api/receipts/save`
6. Backend: Insert into SQLite, optionally add items to pantry

**Recipe Workflow:**
1. iOS: User queries pantry items → POST `/api/cook/suggest` with query string
2. Backend: Send to Claude with pantry context → get recipe suggestions
3. Return `RecipeSuggestion[]` with name, ingredients, instructions, cook time
4. iOS: Display recipes → User selects → POST `/api/cook/deduct` to remove ingredients from pantry

---

*Integration audit: 2026-03-20*
