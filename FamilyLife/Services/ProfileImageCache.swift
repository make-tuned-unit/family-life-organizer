import SwiftUI

@MainActor
@Observable
final class ProfileImageCache {
    private var images: [Int: UIImage] = [:]
    private var pending: Set<Int> = []
    /// Users the server said have no avatar (404) — don't re-fetch every appearance.
    private var missing: Set<Int> = []

    func image(for userId: Int) -> UIImage? {
        images[userId]
    }

    /// Update the cache right after the user picks a new profile image —
    /// without this, your own new avatar never shows until process restart.
    func setImage(_ image: UIImage, for userId: Int) {
        images[userId] = image
        missing.remove(userId)
    }

    /// Drop everything on logout so a second account on the same device
    /// can't see the previous user's cached avatars.
    func clear() {
        images = [:]
        pending = []
        missing = []
        groupImages = [:]
        pendingGroups = []
        missingGroups = []
    }

    func loadFromHousehold(_ members: [APIService.GroupMemberResponse]) {
        for member in members {
            guard let userId = member.user_id, images[userId] == nil else { continue }
            if let base64 = member.profile_image,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                images[userId] = img
                missing.remove(userId)
            }
        }
    }

    func fetchIfNeeded(userId: Int, api: APIService) {
        guard images[userId] == nil, !pending.contains(userId), !missing.contains(userId) else { return }
        pending.insert(userId)
        Task {
            defer { pending.remove(userId) }
            do {
                let base64 = try await api.fetchProfileImage(userId: userId)
                if let data = Data(base64Encoded: base64),
                   let img = UIImage(data: data) {
                    images[userId] = img
                }
            } catch APIError.serverMessage(404, _), APIError.serverError(404) {
                // Known miss — remember so we don't re-fetch on every appearance
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
    }

    /// Pre-load group avatars carried inline in a groups list response.
    func loadFromGroups(_ groups: [APIService.GroupResponse]) {
        for group in groups {
            guard groupImages[group.id] == nil else { continue }
            if let base64 = group.profile_image,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                groupImages[group.id] = img
                missingGroups.remove(group.id)
            }
        }
    }

    func fetchGroupIfNeeded(groupId: Int, api: APIService) {
        guard groupImages[groupId] == nil, !pendingGroups.contains(groupId), !missingGroups.contains(groupId) else { return }
        pendingGroups.insert(groupId)
        Task {
            defer { pendingGroups.remove(groupId) }
            do {
                let base64 = try await api.fetchGroupImage(groupId: groupId)
                if let data = Data(base64Encoded: base64),
                   let img = UIImage(data: data) {
                    groupImages[groupId] = img
                }
            } catch APIError.serverMessage(404, _), APIError.serverError(404) {
                // Known miss — remember so we don't re-fetch on every appearance
                missingGroups.insert(groupId)
            } catch {
                // Network error — silently fall back to initial, retry next appearance
            }
        }
    }
}
