import Foundation
import UIKit

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
    }

    /// Downscale to 256x256 max — prevents full-res UIImage in memory and
    /// eliminates expensive per-frame downscaling in Image(uiImage:).
    private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = UIImage(data: data) else { return nil }
        let maxDim: CGFloat = 256
        let size = source.size
        guard size.width > maxDim || size.height > maxDim else { return source }
        let scale = min(maxDim / size.width, maxDim / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: newSize))
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
            logout()
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
        isRestoringSession = false
        currentUser = nil
        needsOnboarding = false
        UserDefaults.standard.removeObject(forKey: "auth_username")
        UserDefaults.standard.removeObject(forKey: "auth_name")
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "household_invite_code")
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
