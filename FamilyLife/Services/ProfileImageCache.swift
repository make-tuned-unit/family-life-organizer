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
}
