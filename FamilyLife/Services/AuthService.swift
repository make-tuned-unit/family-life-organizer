import Foundation

@Observable
final class AuthService {
    var isAuthenticated = false
    var currentUser: UserProfile?
    var needsOnboarding = false

    struct UserProfile {
        let id: Int?
        let username: String
        let name: String
        let avatar: String
    }

    private let api = APIService()

    init() {
        if let username = UserDefaults.standard.string(forKey: "auth_username"),
           let name = UserDefaults.standard.string(forKey: "auth_name") {
            let id = UserDefaults.standard.integer(forKey: "auth_user_id")
            currentUser = UserProfile(id: id > 0 ? id : nil, username: username, name: name, avatar: "")
            isAuthenticated = true
        }
    }

    func validateSession() async {
        guard isAuthenticated else { return }
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/data") else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                await MainActor.run { logout() }
            }
        } catch {}
    }

    func login(username: String, password: String) async throws {
        let response = try await api.login(username: username, password: password)
        guard response.success, let user = response.user else {
            throw APIError.unauthorized
        }
        currentUser = UserProfile(id: user.id, username: user.username, name: user.name, avatar: user.avatar ?? "")
        isAuthenticated = true

        UserDefaults.standard.set(user.username, forKey: "auth_username")
        UserDefaults.standard.set(user.name, forKey: "auth_name")
        if let id = user.id { UserDefaults.standard.set(id, forKey: "auth_user_id") }
    }

    func register(username: String, password: String, name: String, inviteCode: String? = nil) async throws {
        let response = try await api.register(username: username, password: password, name: name, inviteCode: inviteCode)
        guard response.success, let user = response.user else {
            throw APIError.serverError(400)
        }
        currentUser = UserProfile(id: user.id, username: user.username, name: user.name, avatar: user.avatar ?? "")
        isAuthenticated = true
        needsOnboarding = true

        UserDefaults.standard.set(user.username, forKey: "auth_username")
        UserDefaults.standard.set(user.name, forKey: "auth_name")
        if let id = user.id { UserDefaults.standard.set(id, forKey: "auth_user_id") }

        if let household = response.household {
            UserDefaults.standard.set(household.invite_code, forKey: "household_invite_code")
        }
    }

    func logout() {
        isAuthenticated = false
        currentUser = nil
        needsOnboarding = false
        UserDefaults.standard.removeObject(forKey: "auth_username")
        UserDefaults.standard.removeObject(forKey: "auth_name")
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "household_invite_code")
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
