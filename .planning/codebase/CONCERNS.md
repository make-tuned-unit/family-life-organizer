# Codebase Concerns

**Analysis Date:** 2026-03-20

## Tech Debt

**Plaintext Credentials in Source Code:**
- Issue: Hardcoded user credentials in Express app with plaintext passwords
- Files: `dashboard.js` (lines 11-14)
- Impact: Production security risk. Any unauthorized access to codebase exposes family login credentials
- Fix approach: Move credentials to environment variables (.env file), use hashing for password comparison, implement proper authentication tokens

**Force-Unwrap Operators Throughout iOS App:**
- Issue: Multiple force-unwraps (!) on values that could be nil
- Files: `FamilyLife/Models/Decision.swift:68`, `FamilyLife/Views/Rivalries/StartRivalryView.swift:11,22`, `FamilyLife/Services/APIService.swift:242,254,264,274`
- Impact: App crashes on unexpected nil values instead of graceful error handling
- Fix approach: Replace with optional chaining, guard statements, or coalescing operators; add proper error messages

**Blanket Error Suppression in ViewModels:**
- Issue: Multiple `catch { }` blocks that silently swallow errors
- Files: `FamilyLife/Views/Expenses/ExpensesViewModel.swift:58`, `FamilyLife/Views/Home/FoodKitchenView.swift:118`
- Impact: Silent failures make debugging difficult and hide network/API issues from users
- Fix approach: Log errors, set error state variables, show inline error messages in UI

**Unused Error Variable in HomeViewModel:**
- Issue: `loadTasks()` and `loadTodayAppointments()` catch errors but don't surface them
- Files: `FamilyLife/Views/Home/HomeViewModel.swift:39-40,48-49`
- Impact: Users don't know if tasks/appointments failed to load; looks like empty state instead of error
- Fix approach: Set error property or show error indicator, make error handling consistent with other methods

**Dynamic SQL Field Construction:**
- Issue: Database update methods build SQL dynamically from object entries
- Files: `database.js:235-240, 356-361, 410-415`
- Impact: SQL injection vulnerability if user input isn't properly validated before reaching DB layer
- Fix approach: Use parameterized queries for all dynamic updates, validate input at API layer

**No Transaction Support for Multi-Step Operations:**
- Issue: Complex operations like receipt scanning with pantry migration are not atomic
- Files: `FamilyLife/Views/Home/FoodKitchenView.swift:118`, `dashboard.js` (saveScannedReceipt endpoint)
- Impact: If second operation fails, first operation leaves data in inconsistent state
- Fix approach: Add transaction support to database layer, wrap related operations in promises/async groups

## Known Bugs

**Null-Safety Issues in Optional Chaining:**
- Symptoms: Various nil-coalescing chains could fail if intermediate values are nil
- Files: `FamilyLife/Views/Home/HomeView.swift:151,163,169,175,180,182`, `FamilyLife/Views/Pantry/PantryView.swift:123,127,141,165`
- Trigger: Accessing household data when family members or items have missing fields
- Workaround: All code paths currently use ?? fallbacks, but mapping logic is fragile

**Calendar Date Boundary Calculation:**
- Symptoms: Off-by-one or month-wrapping errors in date calculations
- Files: `database.js:204-209` (getAppointmentsByMonth), `FamilyLife/Views/Calendar/CalendarView.swift:189-191`
- Trigger: End of year transitions or edge cases on Feb 28/29
- Workaround: Use Calendar.current date component functions consistently, test year-end transitions

**Receipt Image Data Loading:**
- Symptoms: Optional image loading with try? and no fallback display
- Files: `FamilyLife/Views/Expenses/ReceiptScannerView.swift:165`
- Trigger: When selected photo fails to load as Data
- Workaround: Silent failure—UI just doesn't show image

## Security Considerations

**Session Management:**
- Risk: Express sessions use non-secure cookies with no HTTPS enforcement
- Files: `dashboard.js:19-24`
- Current mitigation: Session stored in memory (volatile), local network use only
- Recommendations: Enable secure flag in production, use HTTPS, add CSRF protection, implement token-based auth for mobile

**API Authentication Tokens:**
- Risk: No bearer token or persistent session token for iOS app; relies on cookie-based sessions
- Files: `FamilyLife/Services/APIService.swift`, `FamilyLife/Services/AuthService.swift`
- Current mitigation: Local network only, cookies persisted to HTTPCookieStorage
- Recommendations: Implement JWT or opaque bearer tokens, add token expiry, refresh token rotation

**Data at Rest:**
- Risk: No encryption for UserDefaults storage of auth credentials
- Files: `FamilyLife/Services/AuthService.swift:34-35`
- Current mitigation: Local device only, not synced
- Recommendations: Use Keychain for sensitive auth data instead of UserDefaults

**Hardcoded Domains:**
- Risk: No certificate pinning, vulnerable to MITM if deployed beyond local network
- Files: `FamilyLife/Services/APIService.swift:9`
- Current mitigation: Local network only
- Recommendations: Add certificate pinning, enforce HTTPS in production

## Performance Bottlenecks

**Unindexed Pantry Queries on Location/Category:**
- Problem: PantryView filters all pantry items in memory every time user changes selection
- Files: `FamilyLife/Views/Pantry/PantryView.swift:123`, database queries could have WHERE clauses
- Cause: Client-side filtering of entire pantry list; no server-side query parameters
- Improvement path: Add optional location/category filters to `/api/pantry` endpoint, fetch filtered data only

**Home Dashboard Loads All Data Simultaneously:**
- Problem: HomeView loads 4 independent queries in parallel, blocks UI until slowest completes
- Files: `FamilyLife/Views/Home/HomeViewModel.swift:16-20`
- Cause: All requests use `withTaskGroup`, if one endpoint is slow, entire dashboard stalls
- Improvement path: Load dashboard summary first, then load tasks/appointments asynchronously, show progressive UI

**Large List Rendering in HomeView:**
- Problem: HomeView renders full task and grocery lists without pagination/lazy loading
- Files: `FamilyLife/Views/Home/HomeView.swift` (519 lines, many ForEach without LazyVStack)
- Cause: No virtualization for scrollable lists
- Improvement path: Use LazyVStack with onAppear pagination, limit initial count, lazy-load on scroll

**Date Formatting in Every View:**
- Problem: DateFormatter created fresh in every view method
- Files: Multiple ViewModels (ExpensesViewModel, HomeViewModel, etc.)
- Cause: DateFormatter is expensive to initialize
- Improvement path: Cache DateFormatters as static properties

## Fragile Areas

**Receipt Scanning Pipeline:**
- Files: `FamilyLife/Views/Expenses/ReceiptScannerView.swift`, `dashboard.js` (/api/receipts/scan endpoint)
- Why fragile: Multi-step process (photo → base64 → API → OCR → parse → save) with no rollback; image loading has silent failures
- Safe modification: Add comprehensive error states at each step, add retry logic, validate OCR results before saving
- Test coverage: No tests visible for receipt scanning; photo-to-pantry migration untested

**SwiftData ↔ API Sync:**
- Files: All models in `FamilyLife/Models/`, all ViewModels
- Why fragile: Local SwiftData models loaded at app start; no sync mechanism with remote API; no conflict resolution if data changes on server
- Safe modification: Add versioning/timestamps, implement polling or push notifications for updates, ensure SwiftData models stay in sync
- Test coverage: No visible tests for model synchronization

**Calendar Month Navigation:**
- Files: `FamilyLife/Views/Calendar/CalendarViewModel.swift`, `FamilyLife/Views/Calendar/CalendarView.swift`
- Why fragile: Month navigation changes state and triggers reload; edge cases on year boundaries untested
- Safe modification: Test Feb/Dec transitions thoroughly, validate date calculations before UI update
- Test coverage: No tests visible

**Rivalry End Date Calculation:**
- Files: `FamilyLife/Views/Rivalries/StartRivalryView.swift:11`, `FamilyLife/Views/Rivalries/RivalriesView.swift:182`
- Why fragile: Force-unwraps on Calendar date math; days-to-end calculation uses ?? 0 fallback
- Safe modification: Use guards on date calculations, handle nil cases explicitly
- Test coverage: No tests visible for rivalry duration logic

## Scaling Limits

**In-Memory Express Session Store:**
- Current capacity: Single server, sessions stored in Node memory
- Limit: Restarting server loses all sessions; can't scale to multiple instances
- Scaling path: Move to persistent session store (Redis, database), add session cleanup/expiry

**SQLite Single-File Database:**
- Current capacity: Good for household data (~100K records), suitable for 1-2 users
- Limit: No built-in replication, backup must be manual, concurrent writes can lock database
- Scaling path: Evaluate PostgreSQL if multi-family deployment needed, implement incremental backups

**Receipt OCR Processing (if external API):**
- Current capacity: Unknown - depends on external service provider
- Limit: API rate limits not enforced in code
- Scaling path: Add request queuing, implement exponential backoff on 429 responses

## Dependencies at Risk

**express-session Without Persistent Store:**
- Risk: In-memory sessions evaporate on server restart
- Impact: Users forced to re-login after deployment
- Migration plan: Add Redis or database-backed session store before multi-instance deployment

**Base64 Receipt Images:**
- Risk: Transmitting full base64 image data for every scan; no compression
- Impact: Network overhead, slow uploads on mobile
- Migration plan: Switch to multipart form upload with binary image data and optional compression

**hardcoded USERS object in dashboard.js:**
- Risk: Can't add new family members without code changes
- Impact: Inflexible authentication, requires deployment to add users
- Migration plan: Load users from database, implement proper user management endpoints

## Missing Critical Features

**No Offline Support:**
- Problem: iOS app requires constant connectivity to Express backend
- Blocks: Using app on flights, in remote areas; data loss if connection drops mid-operation
- Priority: Medium - affects user experience but not core functionality

**No Sync Conflict Resolution:**
- Problem: No mechanism if same data modified on web and iOS simultaneously
- Blocks: Multi-device workflows
- Priority: Medium - important for Sophie to use web app and iOS simultaneously

**No Audit Trail:**
- Problem: No record of who changed what and when
- Blocks: Family dispute resolution ("Who ate the last cookie?"), debugging
- Priority: Low - nice-to-have for future accountability

**No Webhook Support:**
- Problem: iOS app can't receive push notifications for new tasks/appointments
- Blocks: Real-time updates
- Priority: Medium - would improve UX significantly

## Test Coverage Gaps

**API Service:**
- What's not tested: Error responses (401, 500), network timeouts, malformed JSON responses, URL encoding of parameters
- Files: `FamilyLife/Services/APIService.swift` (306 lines)
- Risk: Silent failures in production when API returns unexpected formats
- Priority: High - API is critical path

**View Models:**
- What's not tested: Error state handling, concurrent data loads, rapid user interactions (e.g., clicking complete multiple times)
- Files: `FamilyLife/Views/*/‌*ViewModel.swift` (HomeViewModel, CalendarViewModel, ExpensesViewModel, PantryViewModel, etc.)
- Risk: UI crashes or shows stale data under stress
- Priority: High

**Database Layer:**
- What's not tested: SQL injection with malicious input, concurrent writes, large dataset performance
- Files: `database.js` (586 lines)
- Risk: Data corruption, security vulnerability, performance degradation
- Priority: High

**Receipt Scanning:**
- What's not tested: Image handling (rotated photos, poor lighting), OCR accuracy, error recovery
- Files: `FamilyLife/Views/Expenses/ReceiptScannerView.swift`, `/api/receipts/scan` endpoint
- Risk: Garbage data saved to receipts/pantry
- Priority: High

**Calendar View:**
- What's not tested: Month boundary transitions (Feb→Mar, Dec→Jan), leap years, timezone changes
- Files: `FamilyLife/Views/Calendar/CalendarViewModel.swift`, `FamilyLife/Views/Calendar/CalendarView.swift`
- Risk: Appointments missing on month boundaries
- Priority: Medium

---

*Concerns audit: 2026-03-20*
