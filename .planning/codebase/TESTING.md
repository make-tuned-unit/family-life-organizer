# Testing Patterns

**Analysis Date:** 2026-03-20

## Test Framework

**Status: No testing infrastructure detected**

This codebase has:
- No XCTest target in Xcode project
- No test files in repository (no `.swift` files with `Test` or `Spec` suffix)
- No test configuration files (no `*.xctest`, `Package.swift`, or test runner config)
- No CI pipeline visible (no GitHub Actions, fastlane, or similar)

**Recommendation:** Testing should be added as a future phase. Start with unit tests for ViewModels and APIService error handling.

---

## If Testing Were Implemented

The following guidance should be followed if tests are added:

### Expected Test Structure

Given the MVVM architecture with `@Observable` ViewModels, tests would likely follow this pattern:

**Unit Test Example (hypothetical):**
```swift
// Tests/ViewModels/HomeViewModelTests.swift
import XCTest
@testable import FamilyLife

final class HomeViewModelTests: XCTestCase {
    var sut: HomeViewModel!
    var mockAPI: MockAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockAPIService()
        sut = HomeViewModel()
    }

    func testLoadAllFetchesDashboard() async {
        // Arrange
        mockAPI.stubDashboard = APIService.DailySummary(
            tasks_today: 3,
            appointments_today: 1,
            groceries_needed: 5,
            overdue_tasks: 0
        )

        // Act
        await sut.loadAll(api: mockAPI)

        // Assert
        XCTAssertEqual(sut.summary?.tasks_today, 3)
        XCTAssertFalse(sut.isLoading)
    }

    func testCompleteTaskRemovesFromList() async {
        // Arrange
        let taskId = 42
        sut.activeTasks = [
            TaskResponse(id: taskId, /* ... */),
            TaskResponse(id: 43, /* ... */)
        ]

        // Act
        await sut.completeTask(taskId, api: mockAPI)

        // Assert
        XCTAssertFalse(sut.activeTasks.contains { $0.id == taskId })
        XCTAssertEqual(sut.activeTasks.count, 1)
    }
}
```

### Mock Pattern

**MockAPIService:**
Based on APIService's design, mocks would use stubs:
```swift
class MockAPIService: APIService {
    var stubDashboard: APIService.DailySummary?
    var stubTasks: [TaskResponse] = []
    var shouldThrowError: APIError?

    override func fetchDashboard() async throws -> APIService.DashboardData {
        if let error = shouldThrowError {
            throw error
        }
        return APIService.DashboardData(
            summary: stubDashboard ?? APIService.DailySummary(tasks_today: 0, appointments_today: 0, groceries_needed: 0, overdue_tasks: 0),
            groceries: []
        )
    }
}
```

### What Should Be Tested

**ViewModels (High Priority):**
- Data loading: `loadAll()`, `loadMonth()`, `load()` methods
- Computed properties: `filteredItems`, `monthYearString`, `calendarDays`, `displayMonthString`
- State mutations: `completeTask()`, `deleteItem()`, `addItem()` removing/updating internal lists
- Error handling: Verify error messages set correctly on API failure
- Navigation helpers: `previousMonth()`, `nextMonth()` date calculations

**Examples to test:**
- `HomeViewModel.loadAll(api:)` - Verify summary and tasks loaded
- `CalendarViewModel.calendarDays` - Verify grid includes padding for previous/next month
- `CalendarViewModel.appointmentCount(for:)` - Verify filtering by date
- `PantryViewModel.filteredItems` - Verify location and search filters work together
- `ExpensesViewModel.monthParam` - Verify date formatting matches API contract

**APIService (Medium Priority):**
- Error handling: `.unauthorized`, `.serverError(_)`, `.invalidResponse` paths
- HTTP method correctness: Verify POST for adds, PUT for updates, DELETE for removes
- Request formation: Query parameters, body encoding, headers
- Response decoding: Verify Codable models decode API responses

**Views (Low Priority):**
- SwiftUI previews sufficient for UI validation
- Snapshot testing if visual regression prevention is needed
- Focus testing on complex layout logic (Calendar grid, filtered lists)

### What NOT to Test

- SwiftUI view rendering (covered by previews and manual testing)
- Asset loading (Colors, SF Symbols)
- UserDefaults integration (AuthService credential persistence) — requires environment setup
- Navigation/routing logic (view presentation) — integration test scope

---

## Test File Organization

**If tests were added, location would be:**

```
FamilyLife.xcodeproj/
├── FamilyLife/                 # Main app target
│   └── ...                    # (existing files)
└── FamilyLifeTests/           # NEW test target
    ├── ViewModels/
    │   ├── HomeViewModelTests.swift
    │   ├── CalendarViewModelTests.swift
    │   ├── PantryViewModelTests.swift
    │   └── ExpensesViewModelTests.swift
    ├── Services/
    │   ├── APIServiceTests.swift
    │   ├── AuthServiceTests.swift
    │   └── Mocks/
    │       ├── MockAPIService.swift
    │       └── MockAuthService.swift
    └── Helpers/
        ├── TestData.swift
        └── XCTestCase+Extensions.swift
```

**Naming convention:**
- Test file: `[Component]Tests.swift`
- Test class: `[Component]Tests: XCTestCase`
- Test method: `test[Scenario][Expected]()` (e.g., `testLoadAllFetchesDashboard()`, `testCompleteTaskRemovesFromList()`)

---

## Run Commands (If Implemented)

```bash
# Run all tests
xcodebuild test -scheme FamilyLife -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
xcodebuild test -scheme FamilyLife -testClass HomeViewModelTests

# Watch mode (continuous)
xcodebuild test -scheme FamilyLife -destination 'platform=iOS Simulator' -watch

# Coverage report
xcodebuild test -scheme FamilyLife -resultBundlePath ./results.xcresult -enableCodeCoverage YES
xcrun xccov view ./results.xcresult

# Run on device
xcodebuild test -scheme FamilyLife -destination 'platform=iOS,name=Jesse's iPhone'
```

---

## Test Types

**Unit Tests (Primary):**
- Scope: Individual ViewModels, APIService error handling, computed properties
- Framework: XCTest with Combine/async-await support
- No external dependencies or network calls (mocks only)

**Integration Tests (Secondary):**
- Scope: APIService + actual HTTP calls to local dev server
- Setup: Start Express backend on `http://localhost:3456` before running
- Example: `testAuthLoginIntegration()` — actual login flow

**UI/Snapshot Tests (Future):**
- Scope: Complex view layouts (Calendar grid, filtered lists)
- Framework: `SnapshotTesting` package (would be added dependency)
- Example: `testCalendarGridRenders()` — verify month layout matches design

**E2E Tests (Not Recommended):**
- Avoid: Full app navigation flow tests are fragile in SwiftUI
- Use manual testing + unit tests on ViewModels instead

---

## Async/Await Testing

**Pattern for testing async ViewModel methods:**

```swift
func testLoadAllConcurrentlyLoadsData() async {
    // Test concurrent task loading with await
    await sut.loadAll(api: mockAPI)

    // Assertions on state after completion
    XCTAssertNotNil(sut.summary)
    XCTAssertFalse(sut.isLoading)
}

// In test class, tests must be async:
@Test
func testCompleteTaskUpdatesState() async throws {
    let id = 1
    try await sut.completeTask(id, api: mockAPI)
    XCTAssertFalse(sut.activeTasks.contains { $0.id == id })
}
```

---

## Error Testing

**Pattern for testing error paths:**

```swift
func testLoadAllSetsErrorOnFailure() async {
    // Arrange
    mockAPI.shouldThrowError = .serverError(500)

    // Act
    await sut.loadAll(api: mockAPI)

    // Assert
    XCTAssertEqual(sut.error, "Server error (500)")
    XCTAssertTrue(sut.activeTasks.isEmpty)
}

func testUnauthorizedErrorClears() async {
    // Arrange
    mockAPI.shouldThrowError = .unauthorized

    // Act
    await sut.loadAll(api: mockAPI)

    // Assert
    XCTAssertEqual(sut.error, "Please sign in again")
}
```

---

## Coverage Goals (If Implemented)

**Recommended targets:**
- ViewModels: 80%+ coverage (core business logic)
- APIService: 75%+ coverage (error paths + HTTP methods)
- Models: 0% (Codable conformance tested via actual API responses)
- Views: 0% (SwiftUI preview validation sufficient)

**Not enforced:** No CI gate currently, but should target 70%+ overall if testing is added.

---

*Testing analysis: 2026-03-20*
