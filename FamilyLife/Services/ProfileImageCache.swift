import SwiftUI

@MainActor
@Observable
final class ProfileImageCache {
    private var images: [Int: UIImage] = [:]
    private var pending: Set<Int> = []

    func image(for userId: Int) -> UIImage? {
        images[userId]
    }

    func loadFromHousehold(_ members: [APIService.GroupMemberResponse]) {
        for member in members {
            guard let userId = member.user_id, images[userId] == nil else { continue }
            if let base64 = member.profile_image,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                images[userId] = img
            }
        }
    }

    func fetchIfNeeded(userId: Int, api: APIService) {
        guard images[userId] == nil, !pending.contains(userId) else { return }
        pending.insert(userId)
        Task {
            defer { pending.remove(userId) }
            do {
                let base64 = try await api.fetchProfileImage(userId: userId)
                if let data = Data(base64Encoded: base64),
                   let img = UIImage(data: data) {
                    images[userId] = img
                }
            } catch {
                // No avatar or network error — silently fall back to initial
            }
        }
    }

    // MARK: - Group / household images

    private var groupImages: [Int: UIImage] = [:]
    private var pendingGroups: Set<Int> = []

    func groupImage(for groupId: Int) -> UIImage? {
        groupImages[groupId]
    }

    /// Update the cache right after the user picks a new group image.
    func setGroupImage(_ image: UIImage, for groupId: Int) {
        groupImages[groupId] = image
    }

    /// Pre-load group avatars carried inline in a groups list response.
    func loadFromGroups(_ groups: [APIService.GroupResponse]) {
        for group in groups {
            guard groupImages[group.id] == nil else { continue }
            if let base64 = group.profile_image,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                groupImages[group.id] = img
            }
        }
    }

    func fetchGroupIfNeeded(groupId: Int, api: APIService) {
        guard groupImages[groupId] == nil, !pendingGroups.contains(groupId) else { return }
        pendingGroups.insert(groupId)
        Task {
            defer { pendingGroups.remove(groupId) }
            do {
                let base64 = try await api.fetchGroupImage(groupId: groupId)
                if let data = Data(base64Encoded: base64),
                   let img = UIImage(data: data) {
                    groupImages[groupId] = img
                }
            } catch {
                // No avatar or network error — silently fall back to initial
            }
        }
    }
}
