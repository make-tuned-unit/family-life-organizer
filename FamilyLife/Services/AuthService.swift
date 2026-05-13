import Foundation
import UIKit
import Security

@MainActor
@Observable
final class AuthService {
    var isAuthenticated = false
    var isRestoringSession = false
    var currentUser: UserProfile?
    var needsOnboarding = false

    /// Thumbnail-sized UIImage for ProfileAvatar (max 256x256)
    private(set) var profileUIImage: UIImage?

    /// Raw image data — only used for disk persistence, not for rendering.
    @ObservationIgnored
    private var profileImageData: Data?

    struct UserProfile: Equatable {
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
            isRestoringSession = true
        }
        profileImageData = Self.loadProfileImageFromDisk()
        if let profileImageData {
            profileUIImage = Self.thumbnail(from: profileImageData)
        }
    }

    func setProfileImage(_ data: Data) {
        let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.6) ?? data
        profileImageData = compressed
        profileUIImage = Self.thumbnail(from: compressed)
        try? compressed.write(to: Self.profileImageURL)
        UserDefaults.standard.removeObject(forKey: "profile_image")

        // Sync to server so other users can see our profile picture
        Task {
            try? await api.uploadProfileImage(compressed.base64EncodedString())
        }
    }

    /// Pre-renders a circular thumbnail at 128x128. The circular crop is baked into the
    /// UIImage so ProfileAvatar needs NO .clipShape or .mask (zero offscreen render passes).
    private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = UIImage(data: data) else { return nil }
        let dim: CGFloat = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: dim, height: dim))
            UIBezierPath(ovalIn: rect).addClip()
            // Center-crop the source into the circle
            let srcSize = source.size
            let scale = max(dim / srcSize.width, dim / srcSize.height)
            let drawSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
            let drawOrigin = CGPoint(x: (dim - drawSize.width) / 2, y: (dim - drawSize.height) / 2)
            source.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    private static var profileImageURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_image.jpg")
    }

    private static func loadProfileImageFromDisk() -> Data? {
        if let data = try? Data(contentsOf: profileImageURL) { return data }
        if let legacy = UserDefaults.standard.data(forKey: "profile_image") {
            try? legacy.write(to: profileImageURL)
            UserDefaults.standard.removeObject(forKey: "profile_image")
            return legacy
        }
        return nil
    }

    func validateSession(api: APIService) async {
        guard isAuthenticated else {
            isRestoringSession = false
            return
        }

        do {
            let response = try await api.fetchMe()
            if let user = response.user {
                let profile = UserProfile(
                    id: user.id,
                    username: user.username,
                    name: user.name,
                    avatar: user.avatar ?? ""
                )
                // Only mutate if changed — prevents cascading re-renders
                if currentUser != profile { currentUser = profile }
                UserDefaults.standard.set(user.username, forKey: "auth_username")
                UserDefaults.standard.set(user.name, forKey: "auth_name")
                UserDefaults.standard.set(user.id, forKey: "auth_user_id")
            }
        } catch APIError.unauthorized {
            // Session expired — try silent re-login with saved credentials
            if await silentRelogin(api: api) {
                // Re-validate after successful login
                await validateSession(api: api)
            } else {
                logout()
            }
        } catch {
            // Keep cached credentials for transient connectivity failures.
        }

        isRestoringSession = false
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

        // Save password to Keychain for session restoration
        Self.savePassword(password, for: username)
    }

    func register(username: String, password: String, name: String, inviteCode: String? = nil, householdName: String? = nil) async throws {
        let response = try await api.register(username: username, password: password, name: name, inviteCode: inviteCode, householdName: householdName)
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

        // Save password to Keychain for session restoration
        Self.savePassword(password, for: username)
    }

    func logout() {
        isAuthenticated = false
        isRestoringSession = false
        let username = currentUser?.username
        currentUser = nil
        needsOnboarding = false
        UserDefaults.standard.removeObject(forKey: "auth_username")
        UserDefaults.standard.removeObject(forKey: "auth_name")
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "household_invite_code")
        if let username { Self.deletePassword(for: username) }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Silent Re-login

    private func silentRelogin(api: APIService) async -> Bool {
        guard let username = currentUser?.username ?? UserDefaults.standard.string(forKey: "auth_username"),
              let password = Self.loadPassword(for: username) else {
            return false
        }
        do {
            let response = try await api.login(username: username, password: password)
            return response.success
        } catch {
            return false
        }
    }

    // MARK: - Keychain

    private static let keychainService = "com.atlasatlantic.familylife"

    private static func savePassword(_ password: String, for username: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadPassword(for username: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deletePassword(for username: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username
        ]
        SecItemDelete(query as CFDictionary)
    }
}
