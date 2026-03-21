# Coding Conventions

**Analysis Date:** 2026-03-20

## Naming Patterns

**Files:**
- View files: PascalCase (e.g., `HomeView.swift`, `AddTaskView.swift`)
- ViewModel files: PascalCase + `ViewModel` suffix (e.g., `HomeViewModel.swift`, `CalendarViewModel.swift`)
- Model files: PascalCase (e.g., `FLTask.swift`, `Appointment.swift`, `Receipt.swift`)
- Service files: PascalCase + `Service` suffix (e.g., `APIService.swift`, `AuthService.swift`)
- Component files: PascalCase (e.g., `AmbientBackground.swift`)

**Functions:**
- camelCase for all function names (e.g., `loadAll()`, `completeTask()`, `dateString()`)
- API methods use verb-noun pattern (e.g., `fetchTasks()`, `addTask()`, `deleteReceipt()`, `suggestRecipes()`)
- Private helper functions prefixed with `private` access modifier (e.g., `private func priorityColor()`, `private func save()`)
- Static helper functions in ViewModels (e.g., `static func dateString()`, `static func todayString()`)

**Variables:**
- camelCase for all property names (e.g., `isLoading`, `selectedDate`, `monthAppointments`)
- State properties prefixed with underscore for private use (e.g., `@State private var showingAddTask`)
- Computed properties follow camelCase (e.g., `filteredItems`, `monthYearString`, `calendarDays`)
- Boolean properties use `is/has/should` prefix convention (e.g., `isLoading`, `isAuthenticated`, `hasDueDate`, `isCurrentMonth`, `isToday`)

**Types:**
- Model classes: PascalCase, marked `@Model` for SwiftData (e.g., `FLTask`, `Appointment`, `Grocery`)
- Response structs: PascalCase + `Response` suffix (e.g., `TaskResponse`, `AppointmentResponse`, `GroceryResponse`)
- Error enums: PascalCase (e.g., `APIError`)
- Nested structs/types: PascalCase (e.g., `UserProfile`, `DailySummary`, `CalendarDay`)

## Code Style

**Formatting:**
- No explicit formatter configured; code appears hand-formatted with:
  - 4-space indentation (Swift standard)
  - Blank lines between logical sections
  - Comments using `//` for single-line and `/* */` for blocks (minimal usage)

**Linting:**
- No `.swiftlint.yml` or linting configuration detected
- Code follows Swift conventions by convention only

## Import Organization

**Order:**
1. Foundation imports first (e.g., `import Foundation`)
2. Framework imports second (e.g., `import SwiftUI`, `import SwiftData`)
3. No relative imports (single-module project)

**Path Aliases:**
- None used; all imports are from Apple frameworks

**Examples:**
```swift
import SwiftUI
import SwiftData
```

## Error Handling

**Patterns:**
- Errors thrown as custom enums (e.g., `APIError` with cases: `.invalidResponse`, `.unauthorized`, `.serverError(Int)`)
- All errors conform to `LocalizedError` for user-facing messages
- `async throws` pattern used throughout API service and ViewModels
- Error handling in ViewModels uses `do-catch` blocks with silent failures:
  ```swift
  do {
      try await api.fetchTasks()
  } catch {
      // Silent failure or set error property: self.error = error.localizedDescription
  }
  ```
- ViewModel error property: `var error: String?` for UI display
- API errors include descriptive messages: `"Invalid server response"`, `"Please sign in again"`, `"Server error (XXX)"`

## Logging

**Framework:** console (implicit; no logging framework detected)

**Patterns:**
- No structured logging; errors handled via exception catching
- Error messages propagated to UI via ViewModel properties (e.g., `self.error`)
- Silent failures preferred in some ViewModels (empty catch blocks)

## Comments

**When to Comment:**
- Component documentation: JSDoc-style comments above structs (e.g., `/// A rich gradient background...`)
- MARK sections used to organize ViewModel methods:
  ```swift
  // MARK: - Auth
  // MARK: - Dashboard
  // MARK: - Tasks
  // MARK: - Networking
  // MARK: - Helpers
  ```
- Comments explain intent, not obvious code

**JSDoc/TSDoc:**
- Documentation comments (triple-slash `///`) used for public types:
  ```swift
  /// A rich gradient background that gives Liquid Glass surfaces something to refract through.
  /// Use as `.background { AmbientBackground() }` on ScrollViews and main content views.
  struct AmbientBackground: View {
  ```

## Function Design

**Size:** Generally compact (20-50 lines for complex methods like `calendarDays` computed property; 5-15 lines for typical API calls)

**Parameters:**
- Use trailing closures for callbacks (e.g., `let onSave: ([String: Any]) -> Void`)
- Default parameter values for optional context (e.g., `init(baseURL: String = "http://localhost:3456")`)
- `self.` used explicitly when passing `api` or `api` service to async methods

**Return Values:**
- Single return type or tuple for multiple values
- Computed properties over methods where appropriate (e.g., `var filteredItems: [PantryItemResponse]`)
- Async methods return `Void` for mutations (e.g., `func loadMonth() async`)

## Module Design

**Exports:**
- Views and ViewModels are public structs/classes by default (no explicit access modifiers)
- Services marked `final` (e.g., `final class APIService`, `final class HomeViewModel`)
- Private methods and properties use `private` explicitly

**Barrel Files:**
- No barrel files or index exports detected
- Each View/ViewModel standalone in its directory

## Codable & API Contracts

**Data Transfer:**
- Two-tier pattern: Model (SwiftData) and Response (API JSON mapping)
- Models use snake_case properties converted to camelCase in Response structs
- Example:
  ```swift
  // API Response (snake_case from JSON)
  struct TaskResponse: Codable, Identifiable {
      let due_date: String?
      let created_by: String?
  }

  // Model (camelCase in Swift)
  @Model final class FLTask {
      var dueDate: String?
      var createdBy: String
  }
  ```

## SwiftUI Patterns

**@Observable:**
- All ViewModels use `@Observable` macro with `final class`
- No ObservedObject or StateObject; direct environment injection via `@Environment`

**Environment:**
- Services passed via `.environment(service)` in app root
- Services accessed with `@Environment(APIService.self) private var api`
- No custom EnvironmentKey needed

**State Management:**
- `@State` for view-local state (toggles, text fields, navigation flags)
- ViewModel properties observed automatically in views decorated with `@State private var viewModel = ViewModel()`
- Error state stored in ViewModels: `var error: String?`

## View Structure

**Common pattern:**
```swift
struct MyView: View {
    @Environment(APIService.self) private var api
    @State private var viewModel = MyViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Sections composed as private computed properties
                header
                content
                details
            }
        }
        .background { AmbientBackground(style: .myStyle) }
        .task { await viewModel.loadData(api: api) }
    }

    private var header: some View { /* ... */ }
}
```

---

*Convention analysis: 2026-03-20*
