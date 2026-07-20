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
        // Encrypt at rest — unreadable while the device is locked.
        try? compressed.write(to: Self.profileImageURL, options: [.completeFileProtection])
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

    func validateSession(api: APIService, attempt: Int = 0) async {
        guard isAuthenticated else {
            isRestoringSession = false
            return
        }
        let gen = sessionGeneration

        do {
            let response = try await api.fetchMe()
            // A logout during the request must not re-persist account state.
            guard gen == sessionGeneration, isAuthenticated else {
                isRestoringSession = false
                return
            }
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
            guard gen == sessionGeneration else {
                isRestoringSession = false
                return
            }
            // Session expired — try silent re-login with the device token.
            switch await silentRelogin(api: api) {
            case .success:
                // Bound the retry: if fetchMe keeps 401ing even after a
                // successful token rotation (e.g. the session cookie never
                // sticks), stop instead of looping and burning a rotation each
                // pass.
                if attempt < 2 {
                    await validateSession(api: api, attempt: attempt + 1)
                } else {
                    logout()
                }
            case .unauthorized:
                // The credential itself is dead (revoked/rotated away).
                logout()
            case .transient:
                // Server hiccup or no connectivity — do NOT log out (which
                // would revoke a perfectly valid token). Keep cached state;
                // the next 401 retries.
                break
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
        // emailSent is false when the server accepted the challenge but code
        // delivery failed (Resend outage, bad address) — the view warns instead
        // of silently waiting for a code that never arrives.
        case needsCode(challenge: String, emailHint: String?, emailSent: Bool)
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
            return .needsCode(challenge: challenge, emailHint: response.email_hint,
                              emailSent: response.email_sent ?? true)
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
        return .needsCode(challenge: challenge, emailHint: r.email_hint,
                          emailSent: r.email_sent ?? true)
    }

    /// Verify the emailed code and finish signing in.
    func verifyLoginCode(challenge: String, code: String) async throws {
        let response = try await api.verifyLoginCode(challenge: challenge, code: code)
        guard response.success == true, let user = response.user else {
            throw APIError.unauthorized
        }
        completeLogin(user: user, refreshToken: response.refresh_token, username: pendingUsername ?? user.username)
    }

    /// Returns whether the server actually sent the code (false on delivery failure).
    @discardableResult
    func resendLoginCode(challenge: String) async throws -> Bool {
        let r = try await api.resendLoginCode(challenge: challenge)
        return r.email_sent ?? true
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
        // Invalidate any in-flight silent re-login so it can't resurrect the
        // session by saving a freshly-rotated token after we've torn down.
        sessionGeneration += 1
        reloginTask?.cancel()
        reloginTask = nil
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
            // Revoke the device + push tokens server-side (best effort), then
            // scrub local credentials.
            let token = Self.loadRefreshToken(for: username)
            let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token")
            let api = self.api
            Task { try? await api.serverLogout(refreshToken: token, deviceToken: deviceToken) }
            Self.deleteRefreshToken(for: username)
            Self.deletePassword(for: username)
        }
        UserDefaults.standard.removeObject(forKey: "apns_device_token")
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Silent Re-login

    enum ReloginOutcome {
        case success
        /// The credential is definitively dead — interactive login required.
        case unauthorized
        /// Network/server hiccup — the credential may still be valid; retry later.
        case transient
    }

    // Single-flight: concurrent 401s (dashboard fan-out) must share ONE
    // re-login. The token rotates on use, so a second racing tokenLogin would
    // present the already-rotated token, get 401, and wrongly wipe the fresh
    // token the winner just saved.
    @ObservationIgnored private var reloginTask: Task<ReloginOutcome, Never>?

    // Bumped on every logout. An in-flight token refresh captures the value at
    // start and refuses to persist a rotated token if it changed mid-flight —
    // otherwise a logout that lands during `await tokenLogin` would be undone by
    // the refresh resuming and re-saving a server-valid credential.
    @ObservationIgnored private var sessionGeneration = 0

    private func silentRelogin(api: APIService) async -> ReloginOutcome {
        if let inFlight = reloginTask {
            return await inFlight.value
        }
        let task = Task { await performSilentRelogin(api: api) }
        reloginTask = task
        let outcome = await task.value
        reloginTask = nil
        return outcome
    }

    private func performSilentRelogin(api: APIService) async -> ReloginOutcome {
        guard let username = currentUser?.username ?? UserDefaults.standard.string(forKey: "auth_username") else {
            return .unauthorized
        }
        let gen = sessionGeneration
        // Preferred path: revocable device token. Rotates on every use.
        if let token = Self.loadRefreshToken(for: username) {
            do {
                let response = try await api.tokenLogin(refreshToken: token)
                // A logout landed while this refresh was in flight — do not
                // persist the rotated token (that would resurrect the session).
                // Best-effort revoke the token the server just handed us.
                if gen != sessionGeneration {
                    if let fresh = response.refresh_token {
                        try? await api.serverLogout(refreshToken: fresh,
                            deviceToken: UserDefaults.standard.string(forKey: "apns_device_token"))
                    }
                    return .unauthorized
                }
                if response.success == true {
                    if let fresh = response.refresh_token {
                        Self.saveRefreshToken(fresh, for: username)
                    }
                    return .success
                }
                return .transient
            } catch {
                // Only a definitive 401 kills the credential. A 500/timeout
                // must not — deleting here would strand a valid token.
                if case APIError.unauthorized = error {
                    Self.deleteRefreshToken(for: username)
                    return .unauthorized
                }
                return .transient
            }
        }
        // Legacy migration: older installs stored the password. Use it once to
        // earn a token, then scrub it. (Only works while 2FA is off.)
        if let password = Self.loadPassword(for: username) {
            do {
                let response = try await api.login(username: username, password: password)
                guard response.success == true else { return .unauthorized }
                if gen != sessionGeneration { return .unauthorized }
                if let token = response.refresh_token {
                    Self.saveRefreshToken(token, for: username)
                    Self.deletePassword(for: username)
                }
                return .success
            } catch {
                if case APIError.unauthorized = error { return .unauthorized }
                return .transient
            }
        }
        return .unauthorized
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
