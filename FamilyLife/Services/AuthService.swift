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
        #if DEBUG
        // Screenshot harness drives a fresh login itself — skip persisted restore so
        // FamilyLifeApp's validateSession path can't race/clobber it (→ login screen).
        if ProcessInfo.processInfo.environment["UITEST_AUTOLOGIN"] != nil {
            return
        }
        #endif
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

    /// Updates the user's display name on the server and in local state.
    func updateName(_ newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let user = currentUser else { return }
        try await api.updateName(trimmed)
        currentUser = UserProfile(id: user.id, username: user.username, name: trimmed, avatar: user.avatar)
        UserDefaults.standard.set(trimmed, forKey: "auth_name")
    }

    /// Changes the user's password on the server, then updates the Keychain copy
    /// so silent re-login (Face ID / saved Passwords) keeps working with the new one.
    func changePassword(current: String, new: String) async throws {
        guard let username = currentUser?.username else { throw APIError.unauthorized }
        try await api.changePassword(currentPassword: current, newPassword: new)
        Self.savePassword(new, for: username)
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

    /// Outcome of the password step under email-2FA.
    enum LoginStep: Equatable {
        case authenticated
        case needsEmailEnrollment(challenge: String)   // first login — no email on file yet
        case needsCode(challenge: String, emailHint: String?)
    }

    // Held between the password step and code verification so we can persist the
    // credential to the Keychain only once 2FA fully succeeds.
    @ObservationIgnored private var pendingUsername: String?
    @ObservationIgnored private var pendingPassword: String?

    func login(username: String, password: String) async throws -> LoginStep {
        let response = try await api.login(username: username, password: password)
        if response.two_factor_required == true, let challenge = response.challenge {
            pendingUsername = username
            pendingPassword = password
            if response.status == "enroll_email" {
                return .needsEmailEnrollment(challenge: challenge)
            }
            return .needsCode(challenge: challenge, emailHint: response.email_hint)
        }
        guard response.success == true, let user = response.user else {
            throw APIError.unauthorized
        }
        completeLogin(user: user, password: password, username: username)
        return .authenticated
    }

    /// First-login: submit the email; server sends a code. Returns the code step.
    func submitLoginEmail(challenge: String, email: String) async throws -> LoginStep {
        let r = try await api.submitLoginEmail(challenge: challenge, email: email)
        return .needsCode(challenge: challenge, emailHint: r.email_hint)
    }

    /// Verify the emailed code and finish signing in.
    func verifyLoginCode(challenge: String, code: String) async throws {
        let response = try await api.verifyLoginCode(challenge: challenge, code: code)
        guard response.success == true, let user = response.user else {
            throw APIError.unauthorized
        }
        completeLogin(user: user, password: pendingPassword, username: pendingUsername ?? user.username)
    }

    func resendLoginCode(challenge: String) async throws {
        _ = try await api.resendLoginCode(challenge: challenge)
    }

    private func completeLogin(user: APIService.UserInfo, password: String?, username: String) {
        currentUser = UserProfile(id: user.id, username: user.username, name: user.name, avatar: user.avatar ?? "")
        isAuthenticated = true
        UserDefaults.standard.set(user.username, forKey: "auth_username")
        UserDefaults.standard.set(user.name, forKey: "auth_name")
        if let id = user.id { UserDefaults.standard.set(id, forKey: "auth_user_id") }
        // Save password to Keychain so the fast password step can autofill / Face ID.
        if let password { Self.savePassword(password, for: username) }
        pendingUsername = nil
        pendingPassword = nil
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
            // Under 2FA, the password step alone can't restore a session (a code is
            // required), so this only succeeds when 2FA is disabled server-side.
            // Otherwise it returns false and the app routes to interactive login.
            let response = try await api.login(username: username, password: password)
            return response.success == true
        } catch {
            return false
        }
    }

    // MARK: - Keychain

    private static let keychainService = "com.mylauft.kinrows"

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
        // Device-only, available after first unlock: never synced to iCloud
        // Keychain and not present in device backups.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
