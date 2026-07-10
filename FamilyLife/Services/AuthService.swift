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

    /// Changes the user's password on the server. The server revokes every
    /// device token and returns a fresh one for THIS device — store it so
    /// silent re-login keeps working here while other devices are signed out.
    func changePassword(current: String, new: String) async throws {
        guard let username = currentUser?.username else { throw APIError.unauthorized }
        let response = try await api.changePassword(currentPassword: current, newPassword: new)
        if let token = response.refresh_token {
            Self.saveRefreshToken(token, for: username)
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

    /// Outcome of the password step under email-2FA.
    enum LoginStep: Equatable {
        case authenticated
        case needsEmailEnrollment(challenge: String)   // first login — no email on file yet
        case needsCode(challenge: String, emailHint: String?)
    }

    // Held between the password step and code verification.
    @ObservationIgnored private var pendingUsername: String?

    func login(username: String, password: String) async throws -> LoginStep {
        let response = try await api.login(username: username, password: password)
        if response.two_factor_required == true, let challenge = response.challenge {
            pendingUsername = username
            if response.status == "enroll_email" {
                return .needsEmailEnrollment(challenge: challenge)
            }
            return .needsCode(challenge: challenge, emailHint: response.email_hint)
        }
        guard response.success == true, let user = response.user else {
            throw APIError.unauthorized
        }
        completeLogin(user: user, refreshToken: response.refresh_token, username: username)
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
        completeLogin(user: user, refreshToken: response.refresh_token, username: pendingUsername ?? user.username)
    }

    func resendLoginCode(challenge: String) async throws {
        _ = try await api.resendLoginCode(challenge: challenge)
    }

    private func completeLogin(user: APIService.UserInfo, refreshToken: String?, username: String) {
        currentUser = UserProfile(id: user.id, username: user.username, name: user.name, avatar: user.avatar ?? "")
        isAuthenticated = true
        UserDefaults.standard.set(user.username, forKey: "auth_username")
        UserDefaults.standard.set(user.name, forKey: "auth_name")
        if let id = user.id { UserDefaults.standard.set(id, forKey: "auth_user_id") }
        // Persist the revocable device token — never the password. Also scrub
        // any password a previous app version left in the Keychain.
        if let refreshToken { Self.saveRefreshToken(refreshToken, for: username) }
        Self.deletePassword(for: username)
        pendingUsername = nil
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

        // Save the device token to the Keychain for session restoration.
        if let token = response.refresh_token {
            Self.saveRefreshToken(token, for: username)
        }
    }

    func logout() {
        isAuthenticated = false
        isRestoringSession = false
        let username = currentUser?.username
        currentUser = nil
        needsOnboarding = false
        profileUIImage = nil
        profileImageData = nil
        try? FileManager.default.removeItem(at: Self.profileImageURL)
        UserDefaults.standard.removeObject(forKey: "auth_username")
        UserDefaults.standard.removeObject(forKey: "auth_name")
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "household_invite_code")
        // Per-account notification watermarks — a fresh account must not
        // inherit (or re-fire against) the previous account's history.
        UserDefaults.standard.removeObject(forKey: "notified_dm_ids")
        UserDefaults.standard.removeObject(forKey: "notified_feed_keys")
        if let username {
            // Revoke the device token server-side (best effort), then scrub
            // local credentials.
            let token = Self.loadRefreshToken(for: username)
            let api = self.api
            Task { try? await api.serverLogout(refreshToken: token) }
            Self.deleteRefreshToken(for: username)
            Self.deletePassword(for: username)
        }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Silent Re-login

    private func silentRelogin(api: APIService) async -> Bool {
        guard let username = currentUser?.username ?? UserDefaults.standard.string(forKey: "auth_username") else {
            return false
        }
        // Preferred path: revocable device token. Rotates on every use.
        if let token = Self.loadRefreshToken(for: username) {
            do {
                let response = try await api.tokenLogin(refreshToken: token)
                if response.success == true {
                    if let fresh = response.refresh_token {
                        Self.saveRefreshToken(fresh, for: username)
                    }
                    return true
                }
            } catch {
                // Revoked/rotated-away token → interactive login. (Don't fall
                // through to the password path on a definitive 401.)
                if case APIError.unauthorized = error {
                    Self.deleteRefreshToken(for: username)
                    return false
                }
            }
            return false
        }
        // Legacy migration: older installs stored the password. Use it once to
        // earn a token, then scrub it. (Only works while 2FA is off.)
        if let password = Self.loadPassword(for: username) {
            do {
                let response = try await api.login(username: username, password: password)
                guard response.success == true else { return false }
                if let token = response.refresh_token {
                    Self.saveRefreshToken(token, for: username)
                    Self.deletePassword(for: username)
                }
                return true
            } catch {
                return false
            }
        }
        return false
    }

    // MARK: - Keychain

    private static let keychainService = "com.mylauft.kinrows"

    // Device refresh token — the ONLY long-lived credential the app keeps.
    // Same device-only, after-first-unlock protection as the old password
    // entry, but revocable server-side and rotated on every use.

    private static func tokenAccount(for username: String) -> String { "\(username)#refresh-token" }

    static func saveRefreshToken(_ token: String, for username: String) {
        savePassword(token, forAccount: tokenAccount(for: username))
    }

    static func loadRefreshToken(for username: String) -> String? {
        loadPassword(forAccount: tokenAccount(for: username))
    }

    static func deleteRefreshToken(for username: String) {
        deletePassword(forAccount: tokenAccount(for: username))
    }

    // Generic Keychain accessors, keyed by account string.

    private static func savePassword(_ value: String, forAccount account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Device-only, available after first unlock: never synced to iCloud
        // Keychain and not present in device backups.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadPassword(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deletePassword(forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Legacy password entries (pre-token installs) are keyed by raw username.
    // Kept read/delete-only for one-time migration in silentRelogin.

    private static func loadPassword(for username: String) -> String? {
        loadPassword(forAccount: username)
    }

    private static func deletePassword(for username: String) {
        deletePassword(forAccount: username)
    }
}
