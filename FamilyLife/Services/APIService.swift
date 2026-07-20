import Foundation
import UIKit

@Observable
final class APIService {
    static let unauthorizedNotification = Notification.Name("APIServiceUnauthorizedNotification")

    var baseURL: String

    private let session: URLSession

    // Single source of truth is AppConfig.apiBaseURL. The UserDefaults
    // override ("server_url") is honored in DEBUG only — in a release build a
    // planted default could silently repoint the app (even to plain http).
    private static var defaultBaseURL: String {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "server_url") ?? AppConfig.apiBaseURL
        #else
        return AppConfig.apiBaseURL
        #endif
    }

    init(baseURL: String = APIService.defaultBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60  // ceiling; AI-backed calls (concierge brief) can run long
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    struct LoginResponse: Codable {
        let success: Bool?
        let user: UserInfo?
        /// Revocable device token — replaces storing the password on device.
        let refresh_token: String?
        // Two-factor fields (present when a code challenge is issued)
        let two_factor_required: Bool?
        let challenge: String?
        let status: String?       // "enroll_email" | "code_sent"
        let email_hint: String?
        let email_sent: Bool?
    }

    struct UserInfo: Codable {
        let id: Int?
        let username: String
        let name: String
        let avatar: String?
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        let body = ["username": username, "password": password, "device_name": Self.deviceName]
        return try await post("/api/auth/login", body: body)
    }

    /// Silent re-login with the stored device token (no password on device).
    /// The server rotates the token; persist the one in the response.
    func tokenLogin(refreshToken: String) async throws -> LoginResponse {
        try await post("/api/auth/token-login", body: ["refresh_token": refreshToken])
    }

    /// Revoke this device's token server-side and destroy the session, and stop
    /// APNs pushes to this device.
    func serverLogout(refreshToken: String?, deviceToken: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let refreshToken { body["refresh_token"] = refreshToken }
        if let deviceToken { body["device_token"] = deviceToken }
        let _: SuccessResponse = try await post("/api/auth/logout", body: body)
    }

    private static var deviceName: String {
        UIDevice.current.name
    }

    /// First-login enrollment: set the email a 2FA code should be sent to.
    func submitLoginEmail(challenge: String, email: String) async throws -> LoginResponse {
        try await post("/api/auth/login/email", body: ["challenge": challenge, "email": email])
    }

    /// Verify the emailed 6-digit code and complete sign-in.
    func verifyLoginCode(challenge: String, code: String) async throws -> LoginResponse {
        try await post("/api/auth/login/verify", body: ["challenge": challenge, "code": code])
    }

    /// Resend a fresh code for an in-flight challenge.
    func resendLoginCode(challenge: String) async throws -> LoginResponse {
        try await post("/api/auth/login/resend", body: ["challenge": challenge])
    }

    // MARK: - Account security (Settings)

    struct SecurityStatus: Codable {
        let email: String?
        let email_verified: Bool
        let two_factor_enabled: Bool
    }

    func fetchSecurityStatus() async throws -> SecurityStatus {
        try await get("/api/account/security")
    }

    struct EmailChangeResponse: Codable {
        let challenge: String
        let email_hint: String?
    }

    func changeAccountEmail(_ email: String) async throws -> EmailChangeResponse {
        try await post("/api/account/email", body: ["email": email])
    }

    func verifyAccountEmail(challenge: String, code: String) async throws {
        let _: SuccessResponse = try await post("/api/account/email/verify", body: ["challenge": challenge, "code": code])
    }

    // MARK: - Dashboard

    struct DashboardData: Codable {
        let summary: DailySummary
        let groceries: [GroceryResponse]
    }

    struct DailySummary: Codable {
        let tasks_today: Int
        let active_tasks: Int?
        let appointments_today: Int
        let groceries_needed: Int
        let overdue_tasks: Int
        let pinned_list_name: String?
    }

    func fetchDashboard() async throws -> DashboardData {
        try await get("/api/data")
    }

    // MARK: - Tasks

    func fetchTasks(status: String? = nil, category: String? = nil) async throws -> [TaskResponse] {
        var params: [String: String] = [:]
        if let status { params["status"] = status }
        if let category { params["category"] = category }
        return try await get("/api/tasks", queryParams: params)
    }

    func addTask(_ task: [String: Any]) async throws {
        let body: [String: Any] = ["type": "task", "data": task]
        let _: SuccessResponse = try await post("/api/add", body: body)
    }

    func completeTask(id: Int) async throws {
        let body: [String: Any] = ["type": "task", "id": id]
        let _: SuccessResponse = try await post("/api/complete", body: body)
    }

    // MARK: - Groceries

    func fetchGroceries(status: String = "needed") async throws -> [GroceryResponse] {
        try await get("/api/groceries", queryParams: ["status": status])
    }

    func addGrocery(item: String, category: String? = nil) async throws {
        var data: [String: Any] = ["item": item]
        if let category { data["category"] = category }
        let body: [String: Any] = ["type": "grocery", "data": data]
        let _: SuccessResponse = try await post("/api/add", body: body)
    }

    func completeGrocery(id: Int) async throws {
        let body: [String: Any] = ["type": "grocery", "id": id]
        let _: SuccessResponse = try await post("/api/complete", body: body)
    }

    // MARK: - Appointments

    func fetchAppointments(dateFrom: String? = nil, dateTo: String? = nil) async throws -> [AppointmentResponse] {
        var params: [String: String] = [:]
        if let dateFrom { params["date_from"] = dateFrom }
        if let dateTo { params["date_to"] = dateTo }
        return try await get("/api/appointments", queryParams: params)
    }

    /// One appointment by id — used to open it from a notification tap.
    func fetchAppointment(id: Int) async throws -> AppointmentResponse {
        try await get("/api/appointments/id/\(id)")
    }

    func fetchAppointmentsByMonth(year: Int, month: Int) async throws -> [AppointmentResponse] {
        try await get("/api/appointments/\(year)/\(month)")
    }

    // MARK: - Household calendar sync (device calendars shared to the household)

    struct SyncedEventResponse: Codable, Identifiable {
        let id: Int
        let owner_id: Int?
        let owner_name: String?
        let calendar_name: String?
        let title: String?
        let location: String?
        let starts_at: String
        let ends_at: String?
        let all_day: Int?
    }

    func syncCalendarEvents(events: [[String: Any]], windowStart: String, windowEnd: String) async throws {
        let body: [String: Any] = ["events": events, "window_start": windowStart, "window_end": windowEnd]
        let _: SuccessResponse = try await post("/api/calendar-sync", body: body)
    }

    func fetchSyncedCalendarEvents(year: Int, month: Int) async throws -> [SyncedEventResponse] {
        try await get("/api/calendar-sync/\(year)/\(month)")
    }

    @discardableResult
    func addAppointment(_ appointment: [String: Any]) async throws -> Int {
        let response: IDResponse = try await post("/api/appointments", body: appointment)
        return response.id
    }

    func deleteAppointment(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/appointments/\(id)")
    }

    func updateAppointment(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/appointments/\(id)", body: data)
    }

    // MARK: - Event Attachments

    func fetchEventAttachments(appointmentId: Int) async throws -> [EventAttachmentResponse] {
        try await get("/api/appointments/\(appointmentId)/attachments")
    }

    func addEventAttachment(appointmentId: Int, type: String, attachmentId: Int) async throws {
        let body: [String: Any] = ["attachment_type": type, "attachment_id": attachmentId]
        let _: SuccessResponse = try await post("/api/appointments/\(appointmentId)/attachments", body: body)
    }

    func deleteEventAttachment(appointmentId: Int, attachmentId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/appointments/\(appointmentId)/attachments/\(attachmentId)")
    }

    // MARK: - Budget

    func fetchBudget(month: String) async throws -> [BudgetSummaryResponse] {
        try await get("/api/budget/\(month)")
    }

    struct BudgetCategoryResponse: Codable, Identifiable {
        let id: Int
        var name: String
        var monthly_limit: Double?
        var color: String?
    }

    func fetchBudgetCategories() async throws -> [BudgetCategoryResponse] {
        try await get("/api/budget-categories")
    }

    func addBudgetCategory(_ data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/budget-categories", body: data)
    }

    func updateBudgetCategory(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/budget-categories/\(id)", body: data)
    }

    func deleteBudgetCategory(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/budget-categories/\(id)")
    }

    // MARK: - Budget Stats

    func fetchBudgetStats(months: Int = 6) async throws -> BudgetStats {
        try await get("/api/budget/stats", queryParams: ["months": String(months)])
    }

    // MARK: - Recurring Payments

    func fetchRecurringPayments() async throws -> [RecurringPayment] {
        try await get("/api/recurring-payments")
    }

    func addRecurringPayment(_ data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/recurring-payments", body: data)
    }

    func updateRecurringPayment(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/recurring-payments/\(id)", body: data)
    }

    func deleteRecurringPayment(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/recurring-payments/\(id)")
    }

    // MARK: - Notes

    func fetchNotes() async throws -> [Note] {
        try await get("/api/notes")
    }

    @discardableResult
    func addNote(_ data: [String: Any]) async throws -> Int {
        let r: IDResponse = try await post("/api/notes", body: data)
        return r.id
    }

    func updateNote(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/notes/\(id)", body: data)
    }

    func deleteNote(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/notes/\(id)")
    }

    // MARK: - Receipts

    func fetchReceipts(month: String? = nil, category: String? = nil) async throws -> [ReceiptResponse] {
        var params: [String: String] = [:]
        if let month { params["month"] = month }
        if let category { params["category"] = category }
        return try await get("/api/receipts", queryParams: params)
    }

    func addReceipt(_ receipt: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/receipts", body: receipt)
    }

    func deleteReceipt(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/receipts/\(id)")
    }

    /// User's "Use cloud AI" privacy setting (Settings → Privacy). Default ON.
    /// Single chokepoint: every Anthropic-backed call checks this so no cloud-AI
    /// route runs when the user has turned it off.
    var cloudAIEnabled: Bool {
        (UserDefaults.standard.object(forKey: "cloudAIEnabled") as? Bool) ?? true
    }

    func scanReceipt(imageData: Data) async throws -> ScanResult {
        guard cloudAIEnabled else { throw APIError.cloudAIDisabled }
        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = ["image": base64]
        return try await post("/api/receipts/scan", body: body)
    }

    @discardableResult
    func saveScannedReceipt(result: ScanResult, category: String, notes: String? = nil, itineraryId: Int? = nil) async throws -> Int {
        var body: [String: Any] = [
            "merchant": result.merchant,
            "date": result.date,
            "total": result.total,
            "category": category
        ]
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let itineraryId { body["itinerary_id"] = itineraryId }
        let response: IDResponse = try await post("/api/receipts/save", body: body)
        return response.id
    }

    // MARK: - Pantry

    func fetchPantry() async throws -> [PantryItemResponse] {
        try await get("/api/pantry")
    }

    func addPantryItem(_ item: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/pantry", body: item)
    }

    func updatePantryItem(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/pantry/\(id)", body: data)
    }

    func deletePantryItem(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/pantry/\(id)")
    }

    // MARK: - Cook

    struct CookResponse: Codable {
        let recipes: [RecipeSuggestion]

        // Lossy array decode: skip AI-generated recipes that fail to decode
        // (e.g. missing name) instead of failing the whole response.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var arr = try c.nestedUnkeyedContainer(forKey: .recipes)
            var out: [RecipeSuggestion] = []
            while !arr.isAtEnd {
                if let recipe = try? arr.decode(RecipeSuggestion.self) {
                    out.append(recipe)
                } else {
                    _ = try? arr.decode(AnyIgnored.self)  // advance past the bad element
                }
            }
            recipes = out
        }
    }

    private struct AnyIgnored: Decodable {
        init(from decoder: Decoder) throws {}  // consumes any element without reading it
    }

    func suggestRecipes(query: String) async throws -> [RecipeSuggestion] {
        guard cloudAIEnabled else { throw APIError.cloudAIDisabled }
        let body: [String: Any] = ["query": query]
        let response: CookResponse = try await post("/api/cook/suggest", body: body)
        return response.recipes
    }

    func deductIngredients(ingredients: [String]) async throws {
        let body: [String: Any] = ["ingredients": ingredients]
        let _: SuccessResponse = try await post("/api/cook/deduct", body: body)
    }

    // MARK: - Concierge

    /// skipAI=true tells the server to make NO Anthropic call (the client will
    /// summarize on-device, or the user turned cloud AI off) — the household data
    /// never leaves the server for the brief.
    func fetchConciergeBrief(forceRefresh: Bool = false, skipAI: Bool = false) async throws -> ConciergeBrief {
        // AI-backed endpoint: allow extra headroom for the Claude round-trip.
        var params: [String: String] = [:]
        if forceRefresh { params["refresh"] = "1" }
        if skipAI { params["skipAI"] = "1" }
        return try await get("/api/concierge/brief", queryParams: params, timeout: 45)
    }

    // MARK: - Subscription

    func verifySubscription(signedTransaction: String) async throws -> SubscriptionStatus {
        try await post("/api/subscription/verify", body: ["signed_transaction": signedTransaction])
    }

    func fetchSubscriptionStatus() async throws -> SubscriptionStatus {
        try await get("/api/subscription/status")
    }

    func sendConciergeMessage(_ message: String, conversationId: Int?) async throws -> ConciergeChatResponse {
        guard cloudAIEnabled else { throw APIError.cloudAIDisabled }
        var body: [String: Any] = ["message": message]
        if let conversationId { body["conversation_id"] = conversationId }
        // Tool-calling loop can take a while — generous timeout.
        return try await post("/api/concierge/chat", body: body, timeout: 60)
    }

    enum ConciergeStreamEvent {
        case delta(String)
        case done(ConciergeChatResponse)
    }

    /// Streaming concierge chat over SSE. Yields `.delta` tokens as they arrive
    /// and a final `.done` with the authoritative reply + actions. The producer
    /// runs off the main actor; consume the stream wherever you update UI.
    func conciergeMessageStream(_ message: String, conversationId: Int?) -> AsyncThrowingStream<ConciergeStreamEvent, Error> {
        let base = baseURL
        let session = self.session
        let enabled = cloudAIEnabled
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    guard enabled else { throw APIError.cloudAIDisabled }
                    guard let url = URL(string: base + "/api/concierge/chat/stream") else { throw APIError.invalidResponse }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120
                    var body: [String: Any] = ["message": message]
                    if let conversationId { body["conversation_id"] = conversationId }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                    if http.statusCode == 401 {
                        NotificationCenter.default.post(name: Self.unauthorizedNotification, object: nil)
                        throw APIError.unauthorized
                    }
                    guard (200...299).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }

                    var pendingEvent = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            pendingEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            guard let data = payload.data(using: .utf8) else { continue }
                            switch pendingEvent {
                            case "delta":
                                if let obj = try? JSONDecoder().decode([String: String].self, from: data),
                                   let t = obj["text"] {
                                    continuation.yield(.delta(t))
                                }
                            case "done":
                                if let r = try? JSONDecoder().decode(ConciergeChatResponse.self, from: data) {
                                    continuation.yield(.done(r))
                                }
                            case "error":
                                let obj = try? JSONDecoder().decode([String: String].self, from: data)
                                throw APIError.streamError(obj?["error"] ?? "Something went wrong.")
                            default:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchConciergeConversations() async throws -> [ConciergeConversationSummary] {
        try await get("/api/concierge/conversations")
    }

    func fetchConciergeMessages(conversationId: Int) async throws -> [ConciergeStoredMessage] {
        try await get("/api/concierge/conversations/\(conversationId)/messages")
    }

    // MARK: - Trips

    func fetchTrips(status: String? = nil) async throws -> [TripResponse] {
        var params: [String: String] = [:]
        if let status { params["status"] = status }
        return try await get("/api/trips", queryParams: params)
    }

    func createTrip(_ trip: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/trips", body: trip)
    }

    func updateTrip(id: Int, updates: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/trips/\(id)", body: updates)
    }

    func arriveTrip(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/trips/\(id)/arrive", body: [:] as [String: String])
    }

    func cancelTrip(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/trips/\(id)/cancel", body: [:] as [String: String])
    }

    func deleteTrip(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/trips/\(id)")
    }

    // MARK: - Family Addresses

    func fetchFamilyAddresses() async throws -> [FamilyAddressResponse] {
        try await get("/api/addresses")
    }

    func addFamilyAddress(_ address: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/addresses", body: address)
    }

    func updateFamilyAddress(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/addresses/\(id)", body: data)
    }

    func deleteFamilyAddress(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/addresses/\(id)")
    }

    // MARK: - Decisions

    func fetchDecisions(status: String? = nil) async throws -> [DecisionResponse] {
        var params: [String: String] = [:]
        if let status { params["status"] = status }
        return try await get("/api/decisions", queryParams: params)
    }

    func fetchDecision(id: Int) async throws -> DecisionResponse {
        try await get("/api/decisions/\(id)")
    }

    @discardableResult
    func addDecision(_ decision: [String: Any]) async throws -> IDResponse {
        try await post("/api/decisions", body: decision)
    }

    func updateDecision(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/decisions/\(id)", body: data)
    }

    func deleteDecision(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/decisions/\(id)")
    }

    func fetchDecisionReactions(id: Int) async throws -> [DecisionReactionResponse] {
        try await get("/api/decisions/\(id)/reactions")
    }

    func setDecisionReaction(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/decisions/\(id)/reactions", body: data)
    }

    func fetchDecisionComments(id: Int) async throws -> [DecisionCommentResponse] {
        try await get("/api/decisions/\(id)/comments")
    }

    func addDecisionComment(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/decisions/\(id)/comments", body: data)
    }

    // MARK: - Rivalries

    func fetchRivalries(status: String? = nil) async throws -> [RivalryResponse] {
        var params: [String: String] = [:]
        if let status { params["status"] = status }
        return try await get("/api/rivalries", queryParams: params)
    }

    func addRivalry(_ rivalry: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/rivalries", body: rivalry)
    }

    func updateRivalry(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/rivalries/\(id)", body: data)
    }

    func fetchRivalryEntries(id: Int) async throws -> [RivalryEntryResponse] {
        try await get("/api/rivalries/\(id)/entries")
    }

    func addRivalryEntry(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/rivalries/\(id)/entries", body: data)
    }

    func fetchRivalryLeaderboard() async throws -> [RivalryLeaderboardResponse] {
        try await get("/api/rivalries/leaderboard")
    }

    func completeRivalry(id: Int) async throws -> RivalryCompleteResponse {
        try await post("/api/rivalries/\(id)/complete", body: [:] as [String: String])
    }

    func deleteRivalry(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/rivalries/\(id)")
    }

    // MARK: - Gifts

    func fetchGiftPeople() async throws -> [GiftPersonResponse] {
        try await get("/api/gifts/people")
    }

    func addGiftPerson(_ person: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/gifts/people", body: person)
    }

    func fetchGiftIdeas(personId: Int? = nil) async throws -> [GiftIdeaResponse] {
        var params: [String: String] = [:]
        if let personId { params["person_id"] = String(personId) }
        return try await get("/api/gifts/ideas", queryParams: params)
    }

    func addGiftIdea(_ idea: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/gifts/ideas", body: idea)
    }

    func updateGiftIdea(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/gifts/ideas/\(id)", body: data)
    }

    func deleteGiftIdea(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/gifts/ideas/\(id)")
    }

    func fetchSpecialEvents() async throws -> [SpecialEventResponse] {
        try await get("/api/gifts/events")
    }

    func addSpecialEvent(_ event: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/gifts/events", body: event)
    }

    func updateSpecialEvent(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/gifts/events/\(id)", body: data)
    }

    func deleteSpecialEvent(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/gifts/events/\(id)")
    }

    // MARK: - People (the household registry: linked users + dependents)

    func fetchPeople() async throws -> [PersonResponse] {
        try await get("/api/people")
    }

    func addPerson(_ person: [String: Any]) async throws {
        let _: IDResponse = try await post("/api/people", body: person)
    }

    func updatePerson(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/people/\(id)", body: data)
    }

    func deletePerson(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/people/\(id)")
    }

    /// Decisions tagged "about" this person — their card's discussion history.
    func fetchPersonDecisions(personId: Int) async throws -> [DecisionResponse] {
        try await get("/api/people/\(personId)/decisions")
    }

    // MARK: - Milestones

    func fetchMilestones(personId: Int? = nil) async throws -> [MilestoneResponse] {
        var params: [String: String] = [:]
        if let personId { params["person_id"] = String(personId) }
        return try await get("/api/milestones", queryParams: params)
    }

    func addMilestone(_ milestone: [String: Any]) async throws {
        let _: IDResponse = try await post("/api/milestones", body: milestone)
    }

    func updateMilestone(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/milestones/\(id)", body: data)
    }

    func deleteMilestone(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/milestones/\(id)")
    }

    // MARK: - Auth (registration)

    struct RegisterResponse: Codable {
        let success: Bool
        let user: UserInfo?
        let refresh_token: String?
        let household: RegisterHousehold?

        struct RegisterHousehold: Codable {
            let id: Int
            let invite_code: String
        }
    }

    struct MeResponse: Codable {
        let user: MeUser?
        let groups: [GroupResponse]

        struct MeUser: Codable {
            let id: Int
            let username: String
            let name: String
            let email: String?
            let phone: String?
            let avatar: String?
        }
    }

    func register(username: String, password: String, name: String, inviteCode: String? = nil, householdName: String? = nil) async throws -> RegisterResponse {
        var body: [String: Any] = ["username": username, "password": password, "name": name, "device_name": Self.deviceName]
        if let inviteCode { body["invite_code"] = inviteCode }
        if let householdName { body["household_name"] = householdName }
        return try await post("/api/auth/register", body: body)
    }

    func fetchMe() async throws -> MeResponse {
        try await get("/api/auth/me")
    }

    // MARK: - Groups

    struct GroupResponse: Codable, Identifiable {
        let id: Int
        var name: String
        var group_type: String
        var description: String?
        var invite_code: String?
        var role: String?
        var member_count: Int?
        var created_by: Int?
        var created_at: String?
        var profile_image: String?  // base64 — set via default so the memberwise init stays callable
            = nil
    }

    struct GroupMemberResponse: Codable, Identifiable {
        let id: Int
        var group_id: Int
        var user_id: Int?
        var contact_id: Int?
        var role: String
        var user_name: String?
        var username: String?
        var user_avatar: String?
        var profile_image: String?
        var contact_name: String?
        var relationship: String?
        var avatar_initial: String?
        var contact_phone: String?

        var displayName: String { user_name ?? contact_name ?? "Unknown" }
        var initial: String { avatar_initial ?? String(displayName.prefix(1)).uppercased() }
    }

    func fetchGroups() async throws -> [GroupResponse] {
        try await get("/api/groups")
    }

    func createGroup(_ data: [String: Any]) async throws -> IDResponse {
        try await post("/api/groups", body: data)
    }

    func joinGroup(inviteCode: String) async throws -> SuccessResponse {
        try await post("/api/groups/join", body: ["invite_code": inviteCode])
    }

    func registerDeviceToken(_ token: String) async throws {
        let _: SuccessResponse = try await post("/api/auth/device-token", body: ["token": token])
    }

    // Location & Presence
    func updateWorkAddress(userId: Int, address: String, lat: Double, lng: Double) async throws {
        let _: SuccessResponse = try await put("/api/users/\(userId)/work-address", body: [
            "work_address": address, "work_lat": lat, "work_lng": lng
        ])
    }

    func clearWorkAddress(userId: Int) async throws {
        let _: SuccessResponse = try await put("/api/users/\(userId)/work-address", body: [
            "work_address": NSNull(), "work_lat": NSNull(), "work_lng": NSNull()
        ])
    }

    struct WorkAddressResponse: Codable {
        let work_address: String?
        let work_lat: Double?
        let work_lng: Double?
    }

    func fetchWorkAddress(userId: Int) async throws -> WorkAddressResponse {
        try await get("/api/users/\(userId)/work-address")
    }

    func reportLocation(lat: Double, lng: Double) async throws -> LocationReportResponse {
        try await post("/api/location", body: ["lat": lat, "lng": lng])
    }

    struct LocationReportResponse: Codable {
        let success: Bool
        let location_name: String?
    }

    struct PresenceMember: Codable, Identifiable {
        let id: Int
        let name: String
        let last_lat: Double?
        let last_lng: Double?
        let last_location_name: String?
        let last_location_at: String?
        let work_address: String?
    }

    func fetchHouseholdPresence() async throws -> [PresenceMember] {
        try await get("/api/household/presence")
    }

    func fetchGroupMembers(groupId: Int) async throws -> [GroupMemberResponse] {
        try await get("/api/groups/\(groupId)/members")
    }

    func addGroupMember(groupId: Int, data: [String: Any]) async throws -> IDResponse {
        try await post("/api/groups/\(groupId)/members", body: data)
    }

    func removeGroupMember(groupId: Int, memberId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/groups/\(groupId)/members/\(memberId)")
    }

    func updateGroup(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/groups/\(id)", body: data)
    }

    func deleteGroup(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/groups/\(id)")
    }

    func leaveGroup(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/groups/\(id)/leave", body: [:] as [String: String])
    }

    // MARK: - Contacts

    struct ContactResponse: Codable, Identifiable {
        let id: Int
        var name: String
        var relationship: String?
        var phone: String?
        var email: String?
        var birthday: String?
        var avatar_initial: String?
        var notes: String?
        var added_by: Int?
        var created_at: String?
    }

    func fetchContacts() async throws -> [ContactResponse] {
        try await get("/api/contacts")
    }

    func addContact(_ data: [String: Any]) async throws -> IDResponse {
        try await post("/api/contacts", body: data)
    }

    func updateContact(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/contacts/\(id)", body: data)
    }

    func deleteContact(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/contacts/\(id)")
    }

    // MARK: - Feed

    struct FeedPostResponse: Codable, Identifiable {
        let id: Int
        var group_id: Int
        var author_id: Int
        var post_type: String
        var title: String?
        var body: String?
        var link_url: String?
        var photo_url: String?
        var reference_type: String?
        var reference_id: Int?
        var author_name: String?
        var author_avatar: String?
        var reaction_count: Int
        var comment_count: Int
        var created_at: String?
    }

    struct FeedCommentResponse: Codable, Identifiable {
        let id: Int
        var user_id: Int?
        var user_name: String?
        var user_avatar: String?
        var text: String
        var created_at: String?
    }

    struct FeedReactionResponse: Codable, Identifiable {
        let id: Int
        var user_name: String?
        var reaction_type: String
    }

    func fetchFeed(groupId: Int, limit: Int = 50, beforeId: Int? = nil) async throws -> [FeedPostResponse] {
        var params: [String: String] = ["limit": String(limit)]
        if let beforeId { params["before_id"] = String(beforeId) }
        return try await get("/api/groups/\(groupId)/feed", queryParams: params)
    }

    func addFeedPost(groupId: Int, data: [String: Any]) async throws -> IDResponse {
        try await post("/api/groups/\(groupId)/feed", body: data)
    }

    func deleteFeedPost(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/feed/\(id)")
    }

    func fetchFeedReactions(postId: Int) async throws -> [FeedReactionResponse] {
        try await get("/api/feed/\(postId)/reactions")
    }

    func addFeedReaction(postId: Int, type: String = "like") async throws {
        let _: SuccessResponse = try await post("/api/feed/\(postId)/reactions", body: ["reaction_type": type])
    }

    func removeFeedReaction(postId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/feed/\(postId)/reactions")
    }

    func fetchFeedComments(postId: Int) async throws -> [FeedCommentResponse] {
        try await get("/api/feed/\(postId)/comments")
    }

    func addFeedComment(postId: Int, text: String) async throws {
        let _: SuccessResponse = try await post("/api/feed/\(postId)/comments", body: ["text": text])
    }

    // MARK: - Budget Projects

    func fetchProjects() async throws -> [ProjectResponse] {
        try await get("/api/projects")
    }

    func addProject(_ project: [String: Any]) async throws -> IDResponse {
        try await post("/api/projects", body: project)
    }

    func deleteProject(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/projects/\(id)")
    }

    func fetchProjectExpenses(projectId: Int) async throws -> [ProjectExpenseResponse] {
        try await get("/api/projects/\(projectId)/expenses")
    }

    func addProjectExpense(projectId: Int, expense: [String: Any]) async throws -> IDResponse {
        try await post("/api/projects/\(projectId)/expenses", body: expense)
    }

    func deleteProjectExpense(projectId: Int, expenseId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/projects/\(projectId)/expenses/\(expenseId)")
    }

    // MARK: - Activity Feed

    struct ActivityItem: Codable, Identifiable {
        let feed_type: String   // decision | event | coverage | post
        let ref_id: Int
        let title: String?
        let body: String?
        let author: String?
        let author_id: Int?
        let status: String?
        let created_at: String?
        let reaction_count: Int?
        let comment_count: Int?
        let group_id: Int?
        let group_name: String?
        let has_photo: Int?    // 1 when a feed post carries a photo (fetched lazily)

        /// Stable key for notification watermarking and list identity
        var stableKey: String { "\(feed_type)-\(ref_id)-\(created_at ?? "")" }

        var id: String { stableKey }

        private enum CodingKeys: String, CodingKey {
            case feed_type, ref_id, title, body, author, author_id, status, created_at, reaction_count, comment_count, group_id, group_name, has_photo
        }
    }

    struct FeedPhotoResponse: Codable {
        let photo_url: String?
    }

    /// Fetch one feed post's photo (base64) — the activity list only carries a flag.
    func fetchFeedPhoto(postId: Int) async throws -> String? {
        let res: FeedPhotoResponse = try await get("/api/feed/\(postId)/photo")
        return res.photo_url
    }

    func fetchActivity(limit: Int = 50) async throws -> [ActivityItem] {
        try await get("/api/activity", queryParams: ["limit": String(limit)])
    }

    // MARK: - Direct Messages

    struct ConversationResponse: Codable, Identifiable {
        let id: Int
        var partner_id: Int
        var partner_name: String
        var partner_image: String?
        var text: String
        var unread_count: Int
        var created_at: String?
        /// Sender of the latest message in this thread (the conversation row is
        /// the newest message regardless of direction). Lets notification logic
        /// suppress a row whose latest message we sent ourselves.
        var sender_id: Int?
    }

    struct DirectMessageResponse: Codable, Identifiable {
        let id: Int
        var sender_id: Int
        var recipient_id: Int
        var sender_name: String?
        var text: String
        var reference_type: String?
        var reference_id: Int?
        var reference_title: String?
        var has_image: Int?
        var image_data: String?  // only set for locally-inserted optimistic messages
        var read_at: String?
        var created_at: String?
    }

    struct UnreadCountResponse: Codable {
        let count: Int
    }

    func fetchConversations() async throws -> [ConversationResponse] {
        try await get("/api/messages")
    }

    func fetchMessages(partnerId: Int, limit: Int = 50, beforeId: Int? = nil) async throws -> [DirectMessageResponse] {
        var params = ["limit": String(limit)]
        if let beforeId { params["before_id"] = String(beforeId) }
        return try await get("/api/messages/\(partnerId)", queryParams: params)
    }

    func sendMessage(recipientId: Int, text: String, referenceType: String? = nil, referenceId: Int? = nil, referenceTitle: String? = nil, imageData: String? = nil) async throws -> IDResponse {
        var body: [String: Any] = ["recipient_id": recipientId, "text": text]
        if let referenceType { body["reference_type"] = referenceType }
        if let referenceId { body["reference_id"] = referenceId }
        if let referenceTitle { body["reference_title"] = referenceTitle }
        if let imageData { body["image_data"] = imageData }
        return try await post("/api/messages", body: body)
    }

    func fetchMessageImage(partnerId: Int, messageId: Int) async throws -> String {
        let response: AvatarResponse = try await get("/api/messages/\(partnerId)/\(messageId)/image")
        return response.image
    }

    func markMessagesRead(partnerId: Int) async throws {
        let _: SuccessResponse = try await post("/api/messages/\(partnerId)/read", body: [:] as [String: String])
    }

    func fetchUnreadMessageCount() async throws -> Int {
        let response: UnreadCountResponse = try await get("/api/messages/unread-count")
        return response.count
    }

    // MARK: - Profile Image

    struct AvatarResponse: Codable {
        let image: String
    }

    func uploadProfileImage(_ base64: String) async throws {
        let _: SuccessResponse = try await put("/api/users/me/avatar", body: ["image": base64])
    }

    /// Permanently delete the signed-in account. Re-auth with the password.
    func deleteAccount(currentPassword: String) async throws {
        let _: SuccessResponse = try await post("/api/account/delete", body: ["current_password": currentPassword])
    }

    func updateName(_ name: String) async throws {
        let _: SuccessResponse = try await put("/api/users/me/name", body: ["name": name])
    }

    struct ChangePasswordResponse: Codable {
        let success: Bool?
        /// Fresh device token — the server revokes all others on password change.
        let refresh_token: String?
    }

    @discardableResult
    func changePassword(currentPassword: String, newPassword: String) async throws -> ChangePasswordResponse {
        try await post("/api/auth/change-password", body: [
            "current_password": currentPassword,
            "new_password": newPassword,
            "device_name": Self.deviceName,
        ])
    }

    func fetchProfileImage(userId: Int) async throws -> String {
        let response: AvatarResponse = try await get("/api/users/\(userId)/avatar")
        return response.image
    }

    func uploadGroupImage(groupId: Int, _ base64: String) async throws {
        let _: SuccessResponse = try await put("/api/groups/\(groupId)/avatar", body: ["image": base64])
    }

    func fetchGroupImage(groupId: Int) async throws -> String {
        let response: AvatarResponse = try await get("/api/groups/\(groupId)/avatar")
        return response.image
    }

    // MARK: - Lists

    struct ListResponse: Codable, Identifiable {
        let id: Int
        var name: String
        var icon: String?
        var color: String?
        var pinned: Int?
        var list_type: String?
        var active_count: Int?
        var total_count: Int?
        var created_at: String?

        var isPinned: Bool { (pinned ?? 0) != 0 }
        var isGrocery: Bool {
            if list_type == "grocery" { return true }
            let n = name.lowercased()
            return n == "groceries" || n == "grocery" || n == "costco" || n == "walmart"
        }
    }

    struct ListItemResponse: Codable, Identifiable {
        let id: Int
        var list_id: Int
        var title: String
        var is_done: Int  // 0 or 1
        var sort_order: Int?
        var added_by: String?
        var category: String?
        var created_at: String?
        var completed_at: String?

        var isDone: Bool { is_done != 0 }
    }

    func fetchLists() async throws -> [ListResponse] {
        try await get("/api/lists")
    }

    func createList(_ data: [String: Any]) async throws -> IDResponse {
        try await post("/api/lists", body: data)
    }

    func updateList(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/lists/\(id)", body: data)
    }

    func deleteList(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/lists/\(id)")
    }

    func pinList(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/lists/\(id)/pin", body: [:] as [String: String])
    }

    func unpinList(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/lists/\(id)/unpin", body: [:] as [String: String])
    }

    func fetchListItems(listId: Int) async throws -> [ListItemResponse] {
        try await get("/api/lists/\(listId)/items")
    }

    func addListItem(listId: Int, title: String) async throws -> IDResponse {
        try await post("/api/lists/\(listId)/items", body: ["title": title])
    }

    func toggleListItem(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/lists/items/\(id)/toggle", body: [:] as [String: String])
    }

    func updateListItem(id: Int, title: String) async throws {
        let _: SuccessResponse = try await put("/api/lists/items/\(id)", body: ["title": title])
    }

    func reorderListItems(listId: Int, orderedIds: [Int]) async throws {
        let _: SuccessResponse = try await post("/api/lists/\(listId)/reorder", body: ["ordered_ids": orderedIds])
    }

    func deleteListItem(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/lists/items/\(id)")
    }

    // MARK: - Coverage / Care Cascade

    struct CoverageRequestResponse: Codable, Identifiable {
        let id: Int
        var requester_id: Int
        var reason: String
        var note: String?
        var status: String
        var approval_count: Int?
        var recipient_count: Int?
        var created_at: String?
    }

    struct CoverageWindowResponse: Codable, Identifiable {
        let id: Int
        var request_id: Int
        var window_date: String
        var start_time: String
        var end_time: String
        var description: String?
    }

    struct CoverageRecipientResponse: Codable, Identifiable {
        let id: Int
        var request_id: Int
        var contact_id: Int
        var invite_token: String?
        var status: String
        var contact_name: String?
        var contact_phone: String?
        var avatar_initial: String?
    }

    struct CoverageApprovalResponse: Codable, Identifiable {
        let id: Int
        var request_id: Int
        var recipient_id: Int
        var window_id: Int
        var approved_date: String
        var approved_start: String
        var approved_end: String
        var helper_note: String?
        var helper_name: String?
        var avatar_initial: String?
        var window_date: String?
        var proposed_start: String?
        var proposed_end: String?
        var created_at: String?
    }

    struct CoverageDetailResponse: Codable {
        let id: Int
        var requester_id: Int
        var reason: String
        var note: String?
        var status: String
        var created_at: String?
        var windows: [CoverageWindowResponse]
        var recipients: [CoverageRecipientResponse]
        var approvals: [CoverageApprovalResponse]
    }

    struct CreateCoverageResponse: Codable {
        let success: Bool
        let id: Int
        let recipients: [RecipientToken]

        struct RecipientToken: Codable {
            let id: Int
            let invite_token: String
        }
    }

    func createCoverageRequest(reason: String, note: String?, windows: [[String: Any]], contactIds: [Int]) async throws -> CreateCoverageResponse {
        let body: [String: Any] = [
            "reason": reason,
            "note": note ?? "",
            "windows": windows,
            "contact_ids": contactIds
        ]
        return try await post("/api/coverage", body: body)
    }

    func fetchCoverageRequests() async throws -> [CoverageRequestResponse] {
        try await get("/api/coverage")
    }

    func fetchCoverageDetail(id: Int) async throws -> CoverageDetailResponse {
        try await get("/api/coverage/\(id)")
    }

    func cancelCoverageRequest(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/coverage/\(id)/cancel", body: [:] as [String: String])
    }

    struct CoverageBlockResponse: Codable, Identifiable {
        let id: Int
        let approved_date: String
        let approved_start: String
        let approved_end: String
        let helper_note: String?
        let helper_name: String
        let reason: String
        let request_id: Int
    }

    func fetchCoverageBlocks(dateFrom: String, dateTo: String) async throws -> [CoverageBlockResponse] {
        try await get("/api/coverage/blocks", queryParams: ["date_from": dateFrom, "date_to": dateTo])
    }

    struct IncomingCoverageRequest: Codable, Identifiable {
        let id: Int
        let reason: String
        let note: String?
        let status: String
        let created_at: String?
        let requester_name: String
        let recipient_id: Int
        let recipient_status: String
        let invite_token: String?
    }

    func fetchIncomingCoverage() async throws -> [IncomingCoverageRequest] {
        try await get("/api/coverage/incoming")
    }

    func approveIncomingCoverage(requestId: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/coverage/incoming/\(requestId)/approve", body: data)
    }

    // MARK: - Itineraries

    func fetchItineraries() async throws -> [ItineraryResponse] {
        try await get("/api/itineraries")
    }

    func createItinerary(_ data: [String: Any]) async throws -> IDResponse {
        try await post("/api/itineraries", body: data)
    }

    func updateItinerary(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/itineraries/\(id)", body: data)
    }

    func deleteItinerary(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/itineraries/\(id)")
    }

    func fetchItineraryStays(itineraryId: Int) async throws -> [ItineraryStayResponse] {
        try await get("/api/itineraries/\(itineraryId)/stays")
    }

    func addItineraryStay(itineraryId: Int, data: [String: Any]) async throws -> IDResponse {
        try await post("/api/itineraries/\(itineraryId)/stays", body: data)
    }

    func updateItineraryStay(itineraryId: Int, stayId: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/itineraries/\(itineraryId)/stays/\(stayId)", body: data)
    }

    func deleteItineraryStay(itineraryId: Int, stayId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/itineraries/\(itineraryId)/stays/\(stayId)")
    }

    func requestStay(stayId: Int) async throws {
        let _: SuccessResponse = try await post("/api/stays/\(stayId)/request", body: [:] as [String: String])
    }

    func respondToStay(stayId: Int, approved: Bool) async throws {
        let _: SuccessResponse = try await post("/api/stays/\(stayId)/respond", body: ["approved": approved])
    }

    func fetchPendingStayRequests() async throws -> [ItineraryStayResponse] {
        try await get("/api/stays/pending")
    }

    struct TripExpensesResponse: Codable {
        let expenses: [ReceiptResponse]
        let total: Double
        let count: Int
    }

    func fetchItineraryExpenses(itineraryId: Int) async throws -> TripExpensesResponse {
        try await get("/api/itineraries/\(itineraryId)/expenses")
    }

    // MARK: - Networking

    struct SuccessResponse: Codable {
        let success: Bool
    }

    struct IDResponse: Codable {
        let success: Bool
        let id: Int
    }

    private func get<T: Decodable>(_ path: String, queryParams: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidResponse
        }
        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let timeout { request.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: Any, timeout: TimeInterval? = nil) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let timeout { request.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, body: Any) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func checkResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: Self.unauthorizedNotification, object: nil)
            throw APIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            // Surface the server's own {error: "..."} message when it sent one —
            // "You can only add your own contacts" beats "Server error (403)".
            if let data,
               let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data),
               let message = body.error, !message.isEmpty {
                throw APIError.serverMessage(http.statusCode, message)
            }
            throw APIError.serverError(http.statusCode)
        }
    }

    private struct ServerErrorBody: Decodable { let error: String? }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case serverMessage(Int, String)
    case cloudAIDisabled
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Please sign in again"
        case .serverError(let code): "Server error (\(code))"
        case .serverMessage(_, let message): message
        case .cloudAIDisabled: "Cloud AI is off. Turn it on in Settings → Privacy to use this feature."
        case .streamError(let msg): msg
        }
    }
}

extension Error {
    /// True for both Swift CancellationError and URLSession cancellation
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
