# Codebase Structure

**Analysis Date:** 2026-03-20

## Directory Layout

```
FamilyLife/
├── App/                    # Application entry, root views, authentication flow
│   ├── FamilyLifeApp.swift        # @main app struct, ModelContainer config
│   ├── ContentView.swift          # Auth gate, MainTabView router
│   └── LoginView.swift            # Login form
├── Views/                  # Feature-organized UI layers
│   ├── Home/               # Dashboard overview, summary cards, quick actions
│   │   ├── HomeView.swift
│   │   ├── HomeViewModel.swift
│   │   ├── AddTaskView.swift
│   │   ├── GroceryListView.swift
│   │   ├── FoodKitchenView.swift
│   │   └── SettingsView.swift
│   ├── Calendar/           # Monthly calendar grid, appointment management
│   │   ├── CalendarView.swift
│   │   ├── CalendarViewModel.swift
│   │   ├── AddAppointmentView.swift
│   │   ├── EditAppointmentView.swift
│   │   └── WeekView.swift
│   ├── Pantry/             # Inventory browser, expiry tracking, item editor
│   │   ├── PantryView.swift
│   │   ├── PantryViewModel.swift
│   │   ├── AddPantryItemView.swift
│   │   └── EditPantryItemView.swift
│   ├── Expenses/           # Budget progress, receipt scanner, receipt list
│   │   ├── ExpensesView.swift
│   │   ├── ExpensesViewModel.swift
│   │   ├── AddReceiptView.swift
│   │   └── ReceiptScannerView.swift
│   ├── Cook/               # AI recipe suggestions, ingredient deduction
│   │   └── CookView.swift
│   ├── Trips/              # Trip planning, status tracking, arrival/cancel
│   │   └── TripsView.swift
│   ├── Rivalries/          # Family competitions, leaderboards, entry logging
│   │   ├── RivalriesView.swift
│   │   ├── StartRivalryView.swift
│   │   ├── RivalryDetailView.swift
│   │   ├── LogProgressView.swift
│   │   └── LeaderboardCard.swift
│   ├── Decisions/          # Family polls, voting, comments
│   │   ├── DecisionsView.swift
│   │   ├── DecisionDetailView.swift
│   │   └── NewDecisionView.swift
│   ├── Gifts/              # Gift tracking per person, purchase status
│   │   ├── GiftsView.swift
│   │   ├── AddGiftPersonView.swift
│   │   └── AddGiftIdeaView.swift
│   └── Components/         # Reusable SwiftUI components
│       └── AmbientBackground.swift
├── Models/                 # Data structures: SwiftData + API response types
│   ├── FLTask.swift              # Task model + TaskResponse
│   ├── Appointment.swift         # Appointment model + AppointmentResponse
│   ├── Grocery.swift             # Grocery model + GroceryResponse
│   ├── Receipt.swift             # Receipt model + ReceiptResponse
│   ├── BudgetCategory.swift      # BudgetCategory model + BudgetSummaryResponse
│   ├── PantryItem.swift          # PantryItem model + PantryItemResponse
│   ├── Trip.swift                # Trip model + TripResponse
│   ├── Rivalry.swift             # Rivalry, RivalryEntry, FamilyMemberPoints models
│   ├── Decision.swift            # Decision, DecisionReaction, DecisionComment models
│   └── Gift.swift                # GiftPerson, GiftIdea, SpecialEvent models
├── Services/               # External integrations, API client, authentication
│   ├── APIService.swift          # REST client for all Express endpoints
│   ├── AuthService.swift         # Authentication state, login/logout
│   ├── HealthKitManager.swift    # Step tracking via Apple HealthKit
│   ├── LocationService.swift     # Location/geocoding services
│   └── NotificationService.swift # Push notification handling
├── Resources/              # Assets, app icon, colors
│   └── Assets.xcassets/          # App icon, accent color
└── FamilyLife.xcodeproj/   # Xcode project configuration
```

## Directory Purposes

**App:**
- Purpose: Application bootstrap and root navigation
- Contains: Entry point, authentication gate, tab view router
- Key files: `FamilyLifeApp.swift` (main), `ContentView.swift` (router)

**Views:**
- Purpose: All user-facing SwiftUI components organized by feature
- Contains: Feature folders (Home, Calendar, Pantry, etc.), modal sheets, reusable components
- Key files: One main View per feature, paired ViewModel, supporting forms/modals

**Models:**
- Purpose: Data contracts and persistence layer
- Contains: SwiftData @Model classes, Codable response structs, enums
- Key files: One file per entity type, paired Model + Response struct

**Services:**
- Purpose: External system integrations
- Contains: HTTP client, authentication, platform integrations (HealthKit, location)
- Key files: APIService (primary), AuthService (secondary), platform managers

**Components:**
- Purpose: Reusable SwiftUI elements
- Contains: Background overlays, card templates, shared styling (when they emerge)
- Key files: Currently only AmbientBackground.swift

**Resources:**
- Purpose: Static assets and app configuration
- Contains: App icon set, accent color definitions
- Key files: Assets.xcassets directory managed by Xcode

## Key File Locations

**Entry Points:**
- `FamilyLife/App/FamilyLifeApp.swift`: Application @main, configures SwiftData ModelContainer with 16 entity types, injects AuthService & APIService as environment
- `FamilyLife/App/ContentView.swift`: Routes between LoginView (not authenticated) and MainTabView (authenticated)

**Configuration:**
- `FamilyLife/App/FamilyLifeApp.swift`: Sets up 16 SwiftData models in modelContainer
- `FamilyLife/Services/APIService.swift`: Base URL initialization with UserDefaults fallback

**Core Logic:**
- `FamilyLife/Services/APIService.swift`: 30+ API endpoints for tasks, groceries, appointments, receipts, pantry, trips, rivalries, decisions, gifts
- `FamilyLife/Views/Home/HomeViewModel.swift`: Parallel loading of dashboard, tasks, appointments
- `FamilyLife/Views/Calendar/CalendarViewModel.swift`: Calendar grid generation, month navigation, appointment filtering

**Testing:**
- No test files present

## Naming Conventions

**Files:**
- `[Feature]View.swift`: Root view for a feature (e.g., HomeView, CalendarView)
- `[Feature]ViewModel.swift`: Paired @Observable class with state and business logic
- `Add[Entity]View.swift`: Modal form for creating an entity (e.g., AddTaskView)
- `Edit[Entity]View.swift`: Modal form for editing an entity (e.g., EditAppointmentView)
- `[Entity].swift`: Model definition with SwiftData @Model and Codable response struct

**Directories:**
- `[Feature]/`: Lowercase feature names (Home, Calendar, Pantry, Expenses)
- Each feature folder contains related views and single ViewModel

**Functions:**
- ViewModel methods: camelCase, action-oriented verbs (loadAll, addTask, completeTask, deleteReceipt)
- APIService methods: camelCase, prefixed with HTTP verb context (fetch*, add*, complete*, delete*, update*, scan*)
- Private helpers: underscore or private keyword (loadDashboard, checkResponse)

**Variables:**
- Properties: camelCase (isLoading, todayAppointments, displayedMonth)
- Computed properties: lowercase descriptive names (monthYearString, calendarDays)
- Constants: UPPER_SNAKE_CASE (rare; mostly inline)

**Types:**
- Models: PascalCase (FLTask, Appointment, GiftPerson)
- Response structs: PascalCase with Response suffix (TaskResponse, AppointmentResponse)
- Enums: PascalCase (ChallengeType, RivalryStatus, GiftIdeaStatus)
- Protocols: Not used yet

## Where to Add New Code

**New Feature (e.g., Chores tracking):**
1. Create folder: `FamilyLife/Views/Chores/`
2. Primary view: `Chores/ChoresView.swift` (main UI)
3. ViewModel: `Chores/ChoresViewModel.swift` (@Observable with loadAll, add, complete, delete methods)
4. Forms: `Chores/AddChoreView.swift`, `Chores/EditChoreView.swift`
5. Model: `Models/Chore.swift` (@Model class + ChoreResponse struct)
6. API methods: Add to `Services/APIService.swift` (new MARK: - Chores section)
7. Route: Add Tab to `MainTabView` in `ContentView.swift`

**New Component (when patterns emerge):**
- Location: `FamilyLife/Views/Components/[ComponentName].swift`
- Example: Budget progress bar used in multiple views → extract to `ProgressCard.swift`

**Utilities/Helpers:**
- General Swift extensions: `FamilyLife/Utils/Extensions.swift` (if created)
- Date/String formatting: Keep in ViewModels initially, extract if used in 3+ places

**Testing:**
- Location: Create `FamilyLifeTests/` target in Xcode
- Naming: `[Feature]ViewModelTests.swift`, `APIServiceTests.swift`
- Mocking: Use URLSession mocking (URLProtocol) for APIService tests

## Special Directories

**Assets.xcassets:**
- Purpose: App icon and color definitions
- Generated: No (managed by Xcode GUI)
- Committed: Yes (contains AccentColor and AppIcon)

**FamilyLife.xcodeproj:**
- Purpose: Xcode project metadata and build configuration
- Generated: No (managed by Xcode, but don't edit .pbxproj by hand)
- Committed: Yes (contains project structure, build settings)

**.git:**
- Purpose: Version control
- Generated: Yes
- Committed: Yes

**.planning/codebase/:**
- Purpose: GSD documentation (this file and ARCHITECTURE.md)
- Generated: No (manually maintained by agent)
- Committed: Yes (reference for future work)

---

*Structure analysis: 2026-03-20*
