# Architecture

**Analysis Date:** 2026-03-20

## Pattern Overview

**Overall:** MVVM (Model-View-ViewModel) with SwiftUI and SwiftData

**Key Characteristics:**
- Unidirectional data flow from Services → ViewModels → Views
- Thin Views that delegate logic to `@Observable` ViewModels
- SwiftData for local persistence, APIService for remote sync
- Environment-based dependency injection (AuthService, APIService)
- Swift Concurrency with async/await throughout

## Layers

**App Layer:**
- Purpose: Application lifecycle, root composition, environment setup
- Location: `FamilyLife/App/FamilyLifeApp.swift`
- Contains: App entry point, ModelContainer configuration, environment provisioning
- Depends on: Services, Models
- Used by: System (iOS)

**View Layer:**
- Purpose: Present UI, capture user input, bind to ViewModels
- Location: `FamilyLife/Views/` (Home, Calendar, Pantry, Expenses, Cook, Trips, Rivalries, Decisions, Gifts)
- Contains: SwiftUI struct Views, modal forms, sheets
- Depends on: ViewModels, Services (via Environment)
- Used by: MainTabView navigation

**ViewModel Layer:**
- Purpose: State management, API orchestration, business logic
- Location: `FamilyLife/Views/{Feature}/` alongside corresponding Views
- Contains: `@Observable` classes (HomeViewModel, CalendarViewModel, ExpensesViewModel, PantryViewModel)
- Depends on: APIService, Models
- Used by: Views via @State initialization

**Service Layer:**
- Purpose: External integrations, authentication, data fetching
- Location: `FamilyLife/Services/`
- Contains: APIService (REST client), AuthService (auth state), HealthKitManager (step tracking), NotificationService, LocationService
- Depends on: None (Foundation frameworks)
- Used by: ViewModels, Views

**Model Layer:**
- Purpose: Data structures for local persistence and API responses
- Location: `FamilyLife/Models/`
- Contains: SwiftData @Model classes (FLTask, Appointment, Grocery, Receipt, PantryItem, etc.) and Codable response structs
- Depends on: Foundation, SwiftData
- Used by: ViewModels, Services

## Data Flow

**Create/Update Flow (User Action):**

1. User interacts with View (e.g., adds task)
2. View calls ViewModel method (e.g., `addTask(_:api:)`)
3. ViewModel calls APIService method (e.g., `api.addTask(_:)`)
4. APIService makes HTTP POST request to Express backend
5. APIService decodes response into Codable struct
6. ViewModel updates local @State properties
7. View re-renders based on ViewModel state changes

**Read Flow (Data Fetch):**

1. View appears (`.task` modifier) or user initiates refresh
2. View calls ViewModel async method (e.g., `loadAll(api:)`)
3. ViewModel creates TaskGroup to parallelize API calls
4. APIService methods execute concurrently via `async let`
5. APIService methods perform HTTP GET and decode responses
6. ViewModel assigns decoded data to properties
7. Views observe changes and re-render

**State Management Strategy:**

- Views hold transient UI state (sheet visibility, selected date, input fields)
- ViewModels hold data state (fetched lists, summary stats, error messages)
- Services hold auth state and manage sessions
- SwiftData provides optional local persistence (models defined but not actively synced)
- No explicit cache invalidation — ViewModels reload on navigation/refresh

**Error Handling Pattern:**

- APIService throws `APIError` enum (invalidResponse, unauthorized, serverError)
- ViewModels catch errors and assign to `error: String?` property
- Views conditionally render error messages inline (no alerts)
- Silent failures common in nested calls (try/catch {} blocks ignore errors)

## Key Abstractions

**APIService:**
- Purpose: Single HTTP client for all Express API endpoints
- Examples: `FamilyLife/Services/APIService.swift`
- Pattern:
  - Methods organized by feature (MARK: comments)
  - Generic `get<T>`, `post<T>`, `put<T>`, `delete<T>` helpers
  - Codable response types defined inline or in Models
  - Session managed with cookie storage for auth
  - Base URL configurable via UserDefaults

**Observable ViewModels:**
- Purpose: Reactive state container with computed properties
- Examples: `HomeViewModel`, `CalendarViewModel`, `ExpensesViewModel`, `PantryViewModel`
- Pattern:
  - `@Observable final class` with no initializer parameters
  - Public @State properties for binding to Views
  - Async methods that take APIService as parameter
  - Private helper methods for data loading logic
  - Computed properties for derived state (monthYearString, monthParam)

**Response & Model Duality:**
- Codable structs (TaskResponse, AppointmentResponse, etc.) decode API responses
- SwiftData @Model classes (FLTask, Appointment, etc.) persist locally
- ViewModels work with API response types; local persistence deferred
- Models include both snake_case API fields and camelCase SwiftData fields

**Navigation Abstraction:**
- MainTabView provides root TabView with 8 tabs
- Each tab wraps a NavigationStack for push navigation
- Modal forms use sheets with callbacks (Closure<Data> -> Void)
- No routing engine; direct View instantiation

## Entry Points

**App Entry:**
- Location: `FamilyLife/App/FamilyLifeApp.swift`
- Triggers: System launch
- Responsibilities: Configure ModelContainer, inject AuthService & APIService as environment objects, display root Scene

**Content Root:**
- Location: `FamilyLife/App/ContentView.swift`
- Triggers: Every frame after @Environment changes
- Responsibilities: Route to LoginView or MainTabView based on authService.isAuthenticated

**Tab Views:**
- HomeView (`FamilyLife/Views/Home/HomeView.swift`): Dashboard with summary stats, active tasks, appointments, shortcuts
- CalendarView (`FamilyLife/Views/Calendar/CalendarView.swift`): Monthly grid with appointment indicators
- PantryView (`FamilyLife/Views/Pantry/PantryView.swift`): Inventory list with expiry filtering
- ExpensesView (`FamilyLife/Views/Expenses/ExpensesView.swift`): Budget + receipt tracking
- TripsView: Active/planned trips with status tracking
- RivalriesView: Family competitions and leaderboards
- DecisionsView: Family decision polls
- GiftsView: Gift ideas organized by person and event

## Error Handling

**Strategy:** Graceful degradation with inline error states

**Patterns:**
- APIError enum distinguishes 401 (unauthorized) from 4xx/5xx (serverError)
- ViewModel `error: String?` property binds to error message Text views
- Most API failures silently return empty arrays (try/catch {} blocks)
- 401 responses should trigger logout (not yet implemented in Views)
- No global error overlay; errors displayed in their context

## Cross-Cutting Concerns

**Logging:** No structured logging; debugging via print() in Services (not visible in production)

**Validation:** Client-side only; views validate before submission (required fields, date ranges). No server-side error aggregation.

**Authentication:**
- AuthService manages login/logout and persists credentials to UserDefaults
- APIService maintains HTTPCookieStorage for session cookies
- No JWT handling; relies on HTTP-only cookies from Express backend
- Auth state injected via @Environment to all views

**Date Formatting:**
- DateFormatter instances created locally in ViewModels (not cached)
- Consistent formats: "yyyy-MM-dd" for dates, "MMMM yyyy" for display
- No timezone awareness; assumes user's local timezone

**Concurrency:**
- Swift Concurrency (async/await) used throughout
- URLSession.data(for:) for all network requests
- TaskGroup for parallel loading of independent requests
- No explicit thread synchronization needed (@Observable handles UI updates)

---

*Architecture analysis: 2026-03-20*
