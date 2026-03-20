# FamilyLife iOS — Product Requirements Document

## 1. Overview

FamilyLife iOS is the native companion to the Family Life Organizer web app. It gives Jesse and Melissa a fast, phone-native way to manage their household — checking calendars, tracking expenses, scanning receipts, managing pantry inventory, and getting AI-powered meal suggestions — all from their iPhones.

### Users

- **Jesse** — primary user, manages household tasks, expenses, groceries
- **Melissa** — co-manager, shares all household data

### Design Philosophy

Clean, minimal, warm. No visual clutter. iPhone-first with iPad layout support. Feels like a personal tool, not enterprise software.

---

## 2. What Exists Today (Web App)

The web app (`family-life-organizer/`) is a Node.js/Express application with SQLite backend that already implements:

### Database (`family.db` — 10 tables)

| Table | Purpose |
|-------|---------|
| `tasks` | Household tasks with category, priority, recurrence, assignment |
| `groceries` | Shopping list (needed/purchased status) |
| `appointments` | Calendar events with date, time, location, person tags |
| `receipts` | Expense records with merchant, amount, category, image path |
| `pantry` | Inventory items with location (fridge/freezer/pantry/counter), expiry dates |
| `budget_categories` | 8 categories with monthly limits (Groceries $800, Dining $300, etc.) |
| `health` | Health metrics (steps, sleep, hydration) |
| `memory` | Long-term knowledge (warranties, preferences) |
| `automations` | Recurring task rules |
| `message_log` | Audit trail of parsed inputs |

### Implemented Features

- **Dashboard** with overview stats, task lists, today's appointments
- **Calendar** with monthly view and appointment highlighting
- **Budget tracker** with category progress bars (spent vs. limit)
- **Grocery list** with add/complete/filter
- **Receipt scanner** using Claude Vision API — extracts items, prices, auto-categorizes
- **Pantry manager** with location-based inventory, expiry tracking, search/filter
- **Cooking assistant** — queries pantry, suggests 3 recipes with available/missing ingredients
- **NLP parser** for natural language task input
- **CLI interface** for quick additions
- **PWA support** with service worker

### API Endpoints (18 routes)

Key routes the iOS app will consume:

- `GET /api/data` — summary + groceries
- `POST /api/add` — add task/grocery
- `POST /api/complete` — mark complete
- `POST /api/appointments` — add appointment
- `POST /api/receipts/scan` — scan receipt image (Claude Vision)
- `POST /api/receipts/save` — save receipt + pantry items
- `GET /pantry`, `POST/PUT/DELETE /api/pantry/:id` — pantry CRUD
- `POST /api/cook/suggest` — AI recipe suggestions
- `POST /api/cook/deduct` — remove used ingredients from pantry

---

## 3. Core Features (iOS)

### 3.1 Home Dashboard

- At-a-glance summary: tasks today, appointments today, groceries needed, overdue count
- Quick-action buttons for common tasks (add grocery, scan receipt)
- Today's appointments list
- Active tasks grouped by category

### 3.2 Calendar

- Monthly calendar view with appointment dots
- Day detail view showing all appointments
- Add/edit appointments with date, time, location, person tags
- Category support: medical, personal, school, daycare

### 3.3 Expenses & Budget

- Monthly budget overview with category progress bars
- 8 budget categories: Groceries ($800), Dining Out ($300), Gas/Transport ($200), Household ($150), Health ($100), Entertainment ($150), Kids ($200), Other ($100)
- Receipt list with merchant, amount, date
- Receipt scanner: camera capture → Claude Vision → auto-extract items and amounts
- Dual save: receipt goes to expenses AND items go to pantry inventory

### 3.4 Grocery List

- Active items with category grouping
- Swipe to mark purchased
- Quick add with natural language support
- Badge count on tab for items needed

### 3.5 Pantry Inventory

- Browse by location: Fridge, Freezer, Pantry, Counter
- Expiry status indicators (fresh/expiring/expired)
- Search and filter
- Add/edit/delete items
- Category support: produce, dairy, meat, bakery, frozen, dry goods, beverages, snacks, household, other
- Link to originating receipt

### 3.6 Cooking Assistant

- Text query: "What can I make for dinner?"
- Queries current pantry inventory
- Returns 3 recipe suggestions with:
  - Name, cook time, difficulty, servings
  - Ingredients available (green) vs. need to buy (red)
  - Step-by-step instructions
- "I made this" action to deduct used ingredients from pantry

---

## 4. New Features (Expanding the Platform)

### 4.1 Feature 7: Family Calendar

A fully-featured shared calendar for all circle members to coordinate family life.

**Visibility & Access:**
- Shared calendar visible to all circle members
- Circle-scoped: each circle has its own calendar (Halifax Family vs. PEI Family)

**Event Types:**
- Appointments (medical, personal, work)
- School events (parent-teacher, field trips, half-days)
- Family trips (vacations, visits, outings)
- Birthdays & anniversaries (auto-recurring annually)
- Recurring events (weekly activities, monthly commitments)

**Event Details:**
- Title, date, time (all-day or specific time)
- Location with map integration
- Notes field for additional context
- Who's attending — select from circle members
- Event type/category for filtering

**Calendar Views:**
- **Month view** — classic grid with event dots
- **Week view** — agenda-style list for busy weeks
- **Day view** — detailed hourly schedule
- Circle color-coding: Halifax family = teal, PEI family = orange (or custom)

**Reminders & Notifications:**
- Default reminders: 1 day before, 1 hour before (configurable per event)
- Push notifications for upcoming events
- "Running late?" quick-action to notify attendees

**Apple Calendar Sync:**
- Two-way sync via EventKit
- Family events appear in Apple Calendar
- External Apple Calendar events appear in FamilyLife with "Busy" indicator
- Opt-in per circle

**Busy Indicators:**
- See when family members are unavailable at a glance
- "Busy" overlay on calendar when Jesse has a work meeting
- Helps coordinate family time without asking "are you free?"

### 4.2 Feature 8: Budget & Financial Tools

Comprehensive budget management with circle-level expense tracking and financial transparency.

**Budget Categories:**
- Groceries
- Dining Out
- Kids (activities, supplies, childcare)
- Household (maintenance, supplies)
- Entertainment
- Travel
- Miscellaneous
- Custom categories per circle

**Monthly Budget Setup:**
- Set monthly spending limits per category
- View at-a-glance: budgeted vs. actual
- Visual progress bars: green (on track), yellow (approaching limit), red (over budget)

**Expense Entry:**
- Quick add: amount, category, optional notes
- Who paid — track which circle member made the purchase
- Circle attribution — assign to specific circle (Halifax vs. PEI)
- Receipt photo attachment (link to receipt scanner)
- Date and merchant auto-filled from receipt scan

**Shared Expenses:**
- Split bills between family members
- "Sophie paid $120 for dinner, split 3 ways" — app tracks who owes what
- Settlement tracking: mark debts as paid
- Monthly summary of splits per member

**Monthly Summary Report:**
- Visual breakdown: where did the money go?
- Pie chart by category
- Comparison to previous month
- Top spending categories flagged

**Rollover Settings:**
- Per-category choice: unspent budget carries forward OR resets monthly
- Example: unspent grocery budget rolls to next month, but entertainment resets
- Visual indicator of rollover amount

**Data Sync:**
- Syncs with existing `family.db` expenses table
- Web app expenses appear in iOS budget
- iOS expenses sync back to web app

### 4.3 Feature 9: Decision Sharing ("What do you think?")

A lightweight social feature for getting family input on decisions big and small.

**Share Anything:**
- Product links (Amazon, stroller, new TV)
- Photos (paint color options, outfit choices, furniture)
- Text ideas ("Thinking of switching daycares...")
- Polls — 2-4 options to vote on

**Content Types:**
- **URL Preview** — auto-fetches title, image, description
- **Photo** — camera roll or camera capture
- **Text** — plain text with optional formatting
- **Poll** — create with 2-4 options, members vote

**Circle Reactions:**
- 👍 Thumbs up
- 👎 Thumbs down
- ❤️ Heart
- 🗳️ Vote (for polls)

**Comments Thread:**
- Threaded discussion on each item
- @mentions for specific family members
- Reply notifications

**Use Case Examples:**
- "Should we get this stroller?" + Amazon link → family votes
- "What do you think of this restaurant for Friday?" + Yelp link
- "Vote: beach or park this weekend?" + poll
- Photo: "Which paint color for the nursery?" A, B, C options

**Item Lifecycle:**
- Items expire after 7 days (configurable)
- Creator can mark as "Resolved" early
- Resolved items move to archive, still searchable
- Auto-cleanup of expired items after 30 days

**Notifications:**
- Push when someone reacts to your item
- Push when someone comments
- Push when a poll closes or reaches consensus
- Daily digest option: "3 new items need your input"

**Discovery:**
- Feed view: latest items from all circles
- Filter by circle
- Filter by type (links, photos, polls)
- Your items vs. items you haven't reacted to

---

## 5. Data & Sync

### Sync Strategy

The iOS app connects to the web app's Express API running on the local network (or via Render deployment). No separate backend needed.

- **API client** talks to the existing Express endpoints
- **Offline cache** using SwiftData for read access when offline
- **Optimistic updates** for writes — update local state immediately, sync to server
- **Pull-to-refresh** on all list views

### Authentication

Session-based auth matching the web app. Login with username/password (Jesse/Melissa).

---

## 6. Technical Requirements

### Platform

- iOS 18.0+
- iPhone (primary), iPad (compatible)
- Xcode 16+

### Stack

- **SwiftUI** — all UI
- **SwiftData** — local persistence and offline cache
- **Swift Concurrency** (async/await) — networking
- **PhotosUI** — receipt photo capture
- **Vision framework** — optional on-device text recognition as fallback

### Architecture

- **MVVM** with `@Observable` view models
- Feature-based folder structure (Views/Home, Views/Calendar, etc.)
- Shared `APIService` for all network calls
- `SyncEngine` managing local ↔ remote state

### Bundle ID

`com.atlasatlantic.familylife`

---

## 7. Design Guidelines

### Visual Style

- Clean white/cream backgrounds with warm accent colors
- SF Symbols throughout
- System typography (SF Pro)
- Rounded cards for content sections
- Subtle shadows, no harsh borders
- Color palette: warm neutrals + a family-friendly accent (soft teal or warm orange)

### Navigation

- Tab bar with 5 tabs: Home, Calendar, Pantry, Expenses, Cook
- Each tab has its own navigation stack
- Sheet presentations for add/edit forms
- Swipe gestures for list actions (complete, delete)

### Accessibility

- Dynamic Type support
- VoiceOver labels on all interactive elements
- Sufficient color contrast

---

## 8. Family Circles & Location Sharing

### 7.1 Family Circles

A **Circle** is a group of family members who share household data.

- **Jesse's Circles:**
  - "Halifax Family" — Sophie, Rowan, Jude, Melissa
  - "PEI Family" — Parents, siblings back home
- **Invitation Flow:**
  - Circle admin invites members via phone number or email
  - Invited member receives link/SMS to download app and accept
  - Members can belong to multiple circles
- **Data Scope:**
  - Each circle has its own shared calendar, expenses, and pantry
  - OR optionally share across circles (Jesse's preference: separate per circle)
  - Easy switcher in app header to toggle between active circles

### 7.2 Live Location & Trip Tracking

Family members can share live location and trip progress within a circle.

**Trip Creation:**
- Manual: Member logs a trip with origin, destination, and ETA
- Auto-detected (see Section 9)

**Live Trip View:**
- Map showing real-time position of traveling member
- Progress bar: % complete based on distance
- ETA countdown
- Trip card with destination and purpose

**Notifications:**
- Push notification when trip starts ("Jesse's parents are on their way!")
- "30 minutes away" alert when approaching destination
- "Arrived safely" confirmation when they reach destination

**Trip History:**
- Saved trips with route, duration, date
- Filter by member or date range
- Useful for tracking regular routes (e.g., parents' monthly visit)

### 7.3 Privacy & Controls

- **Opt-in per trip** — location sharing is NOT always-on
- Member explicitly starts sharing when they begin a trip
- Can stop sharing at any time
- Circle members only see location during active trips
- No background location tracking when not on a trip

---

## 9. Auto-Trip Detection

### 8.1 Overview

Automatically detect when family members begin trips based on location changes, reducing friction for sharing ETA and arrival updates.

### 8.2 Home Location Setup

- Each family member sets a **Home location** (address or map pin)
- Saved once, editable in Settings
- Stored per-member, per-device

### 8.3 Geofence Monitoring

- **500-meter radius** around each member's home location
- Uses **Core Location region monitoring** (CLCircularRegion)
- **Works when app is closed** — iOS wakes app on boundary crossing
- Battery-conscious: uses significant location changes, not continuous GPS

### 8.4 Auto-Detection Flow

| Stage | Trigger | Action |
|-------|---------|--------|
| Departure | Device exits home geofence | App detects departure, checks if moving toward known family address |
| Notification | Confirmed departure | Push to circle: "🚗 Jesse's parents have left home and are on their way!" |
| Destination Match | Heading toward known address | Auto-label destination (e.g., "Jesse's House — Halifax") |
| 30-Min Alert | ETA reaches 30 min | Push: "Jesse's parents are 30 minutes away" |
| Arrival | Enters destination geofence | Push: "Your parents have arrived!" + trip saved to history |

### 8.5 Known Family Addresses

- Automatically populated from circle members' home locations
- Jesse can add custom addresses (e.g., "PEI Family Home")
- Trip matching uses heading + proximity to known destinations

### 8.6 Opt-in & Battery

- **Per-circle opt-in** — members choose which circles can auto-detect their trips
- Significant location change API (not continuous GPS)
- Region monitoring is handled by iOS, minimal battery impact
- Member can disable auto-detection entirely in Settings

### 8.7 Technical Implementation

- **Core Location:** CLLocationManager with startMonitoring(for:)
- **Background modes:** Location updates + Background processing
- **Push notifications:** Apple Push Notification Service (APNs)
- **Trip state:** Stored locally, synced to server when online

---

## 10. Future Considerations

- Push notifications for expiring pantry items
- Shared family widgets (WidgetKit)
- Apple Watch companion for grocery list
- Shortcuts integration for Siri ("Add milk to groceries")
- Apple Health integration for health metrics
- Google Calendar sync
- iCloud sharing between family members
- Live Activities for active trips (Dynamic Island)
