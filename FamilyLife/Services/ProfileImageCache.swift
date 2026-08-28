import SwiftUI

@MainActor
@Observable
final class ProfileImageCache {
    private var images: [Int: UIImage] = [:]
    private var pending: Set<Int> = []
    /// Users the server said have no avatar (404) — don't re-fetch every appearance.
    private var missing: Set<Int> = []
    /// Logged-in user id — disk files live under this namespace so account
    /// switch on the same device cannot show the previous person's avatars.
    private var ownerUserId: Int?

    func image(for userId: Int) -> UIImage? {
        images[userId]
    }

    /// Bind the cache to the signed-in account. Switching users drops memory
    /// (disk for the previous owner is left until `clear()`).
    func setOwner(_ userId: Int) {
        guard ownerUserId != userId else { return }
        images = [:]
        pending = []
        missing = []
        groupImages = [:]
        pendingGroups = []
        missingGroups = []
        ownerUserId = userId
    }

    /// Update the cache right after the user picks a new profile image —
    /// without this, your own new avatar never shows until process restart.
    func setImage(_ image: UIImage, for userId: Int) {
        images[userId] = image
        missing.remove(userId)
        persist(image, file: userFile(userId))
    }

    /// Drop everything on logout so a second account on the same device
    /// can't see the previous user's cached avatars.
    func clear() {
        if let dir = ownerDir() {
            try? FileManager.default.removeItem(at: dir)
        }
        images = [:]
        pending = []
        missing = []
        groupImages = [:]
        pendingGroups = []
        missingGroups = []
        ownerUserId = nil
    }

    func loadFromHousehold(_ members: [APIService.GroupMemberResponse], api: APIService) {
        for member in members {
            guard let userId = member.user_id, images[userId] == nil else { continue }
            if (member.has_avatar ?? 0) == 1 {
                fetchIfNeeded(userId: userId, api: api)
            }
        }
    }

    func fetchIfNeeded(userId: Int, api: APIService, hasAvatar: Bool = true) {
        guard hasAvatar else { missing.insert(userId); return }
        guard images[userId] == nil, !pending.contains(userId), !missing.contains(userId) else { return }
        if let file = userFile(userId),
           let data = try? Data(contentsOf: file),
           let img = UIImage(data: data) {
            images[userId] = img
            return
        }
        pending.insert(userId)
        Task {
            defer { pending.remove(userId) }
            do {
                let payload = try await api.fetchProfileImage(userId: userId)
                if let data = Self.imageData(from: payload),
                   let img = UIImage(data: data) {
                    images[userId] = img
                    persist(img, file: userFile(userId))
                }
            } catch APIError.serverMessage(404, _), APIError.serverError(404) {
                missing.insert(userId)
            } catch {
                // Network error — silently fall back to initial, retry next appearance
            }
        }
    }

    // MARK: - Group / household images

    private var groupImages: [Int: UIImage] = [:]
    private var pendingGroups: Set<Int> = []
    private var missingGroups: Set<Int> = []

    func groupImage(for groupId: Int) -> UIImage? {
        groupImages[groupId]
    }

    /// Update the cache right after the user picks a new group image.
    func setGroupImage(_ image: UIImage, for groupId: Int) {
        groupImages[groupId] = image
        missingGroups.remove(groupId)
        persist(image, file: groupFile(groupId))
    }

    /// Kick off dedicated avatar GETs for groups that have one. List payloads
    /// no longer inline the blob.
    func loadFromGroups(_ groups: [APIService.GroupResponse], api: APIService) {
        for group in groups {
            guard groupImages[group.id] == nil else { continue }
            if (group.has_avatar ?? 0) == 1 {
                fetchGroupIfNeeded(groupId: group.id, api: api)
            }
        }
    }

    func fetchGroupIfNeeded(groupId: Int, api: APIService, hasAvatar: Bool = true) {
        guard hasAvatar else { missingGroups.insert(groupId); return }
        guard groupImages[groupId] == nil, !pendingGroups.contains(groupId), !missingGroups.contains(groupId) else { return }
        if let file = groupFile(groupId),
           let data = try? Data(contentsOf: file),
           let img = UIImage(data: data) {
            groupImages[groupId] = img
            return
        }
        pendingGroups.insert(groupId)
        Task {
            defer { pendingGroups.remove(groupId) }
            do {
                let payload = try await api.fetchGroupImage(groupId: groupId)
                if let data = Self.imageData(from: payload),
                   let img = UIImage(data: data) {
                    groupImages[groupId] = img
                    persist(img, file: groupFile(groupId))
                }
            } catch APIError.serverMessage(404, _), APIError.serverError(404) {
                missingGroups.insert(groupId)
            } catch {
                // Network error — silently fall back to initial, retry next appearance
            }
        }
    }

    // MARK: - Disk

    private func ownerDir() -> URL? {
        guard let ownerUserId else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
            .appendingPathComponent(String(ownerUserId), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func userFile(_ userId: Int) -> URL? {
        ownerDir()?.appendingPathComponent("user-\(userId).jpg")
    }

    private func groupFile(_ groupId: Int) -> URL? {
        ownerDir()?.appendingPathComponent("group-\(groupId).jpg")
    }

    private func persist(_ image: UIImage, file: URL?) {
        guard let file, let jpeg = image.jpegData(compressionQuality: 0.7) else { return }
        try? jpeg.write(to: file, options: .atomic)
    }

    private static func imageData(from payload: String) -> Data? {
        if let range = payload.range(of: "base64,") {
            return Data(base64Encoded: String(payload[range.upperBound...]))
        }
        return Data(base64Encoded: payload)
    }
}
