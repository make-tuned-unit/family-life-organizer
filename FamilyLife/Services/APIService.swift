import Foundation

@Observable
final class APIService {
    var baseURL: String

    private let session: URLSession

    private static var defaultBaseURL: String {
        #if DEBUG
        return "http://localhost:3456"
        #else
        return "https://family-life-organizer-production.up.railway.app"
        #endif
    }

    init(baseURL: String = APIService.defaultBaseURL) {
        self.baseURL = UserDefaults.standard.string(forKey: "server_url") ?? baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    struct LoginResponse: Codable {
        let success: Bool
        let user: UserInfo?
    }

    struct UserInfo: Codable {
        let id: Int?
        let username: String
        let name: String
        let avatar: String?
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        let body = ["username": username, "password": password]
        return try await post("/api/auth/login", body: body)
    }

    // MARK: - Dashboard

    struct DashboardData: Codable {
        let summary: DailySummary
        let groceries: [GroceryResponse]
    }

    struct DailySummary: Codable {
        let tasks_today: Int
        let appointments_today: Int
        let groceries_needed: Int
        let overdue_tasks: Int
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

    func fetchAppointmentsByMonth(year: Int, month: Int) async throws -> [AppointmentResponse] {
        try await get("/api/appointments/\(year)/\(month)")
    }

    func addAppointment(_ appointment: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/appointments", body: appointment)
    }

    func deleteAppointment(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/appointments/\(id)")
    }

    func updateAppointment(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/appointments/\(id)", body: data)
    }

    // MARK: - Budget

    func fetchBudget(month: String) async throws -> [BudgetSummaryResponse] {
        try await get("/api/budget/\(month)")
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

    func scanReceipt(imageData: Data) async throws -> ScanResult {
        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = ["image": base64]
        return try await post("/api/receipts/scan", body: body)
    }

    func saveScannedReceipt(result: ScanResult, addToPantry: Bool) async throws {
        let items = result.items.map { item -> [String: Any] in
            var d: [String: Any] = ["name": item.name]
            if let price = item.price { d["price"] = price }
            if let qty = item.quantity { d["quantity"] = qty }
            return d
        }
        let body: [String: Any] = [
            "merchant": result.merchant,
            "date": result.date,
            "total": result.total,
            "category": result.category,
            "items": items,
            "add_to_pantry": addToPantry
        ]
        let _: SuccessResponse = try await post("/api/receipts/save", body: body)
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
    }

    func suggestRecipes(query: String) async throws -> [RecipeSuggestion] {
        let body: [String: Any] = ["query": query]
        let response: CookResponse = try await post("/api/cook/suggest", body: body)
        return response.recipes
    }

    func deductIngredients(ingredients: [String]) async throws {
        let body: [String: Any] = ["ingredients": ingredients]
        let _: SuccessResponse = try await post("/api/cook/deduct", body: body)
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

    // MARK: - Family Addresses

    func fetchFamilyAddresses() async throws -> [FamilyAddressResponse] {
        try await get("/api/addresses")
    }

    func addFamilyAddress(_ address: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/addresses", body: address)
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

    func addDecision(_ decision: [String: Any]) async throws {
        let _: SuccessResponse = try await post("/api/decisions", body: decision)
    }

    func updateDecision(id: Int, data: [String: Any]) async throws {
        let _: SuccessResponse = try await put("/api/decisions/\(id)", body: data)
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

    func deleteSpecialEvent(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/gifts/events/\(id)")
    }

    // MARK: - Auth (registration)

    struct RegisterResponse: Codable {
        let success: Bool
        let user: UserInfo?
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

    func register(username: String, password: String, name: String, inviteCode: String? = nil) async throws -> RegisterResponse {
        var body: [String: Any] = ["username": username, "password": password, "name": name]
        if let inviteCode { body["invite_code"] = inviteCode }
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

    func fetchGroupMembers(groupId: Int) async throws -> [GroupMemberResponse] {
        try await get("/api/groups/\(groupId)/members")
    }

    func addGroupMember(groupId: Int, data: [String: Any]) async throws -> IDResponse {
        try await post("/api/groups/\(groupId)/members", body: data)
    }

    func removeGroupMember(groupId: Int, memberId: Int) async throws {
        let _: SuccessResponse = try await delete("/api/groups/\(groupId)/members/\(memberId)")
    }

    func deleteGroup(id: Int) async throws {
        let _: SuccessResponse = try await delete("/api/groups/\(id)")
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

    // MARK: - Lists

    struct ListResponse: Codable, Identifiable {
        let id: Int
        var name: String
        var icon: String?
        var color: String?
        var active_count: Int?
        var total_count: Int?
        var created_at: String?
    }

    struct ListItemResponse: Codable, Identifiable {
        let id: Int
        var list_id: Int
        var title: String
        var is_done: Int  // 0 or 1
        var sort_order: Int?
        var added_by: String?
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

    func fetchListItems(listId: Int) async throws -> [ListItemResponse] {
        try await get("/api/lists/\(listId)/items")
    }

    func addListItem(listId: Int, title: String) async throws -> IDResponse {
        try await post("/api/lists/\(listId)/items", body: ["title": title])
    }

    func toggleListItem(id: Int) async throws {
        let _: SuccessResponse = try await post("/api/lists/items/\(id)/toggle", body: [:] as [String: String])
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

    // MARK: - Networking

    struct SuccessResponse: Codable {
        let success: Bool
    }

    struct IDResponse: Codable {
        let success: Bool
        let id: Int
    }

    private func get<T: Decodable>(_ path: String, queryParams: [String: String] = [:]) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidResponse
        }
        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: Any) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, body: Any) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Please sign in again"
        case .serverError(let code): "Server error (\(code))"
        }
    }
}
