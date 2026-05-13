import SwiftUI

@MainActor
@Observable
final class MessageCache {
    /// Cached messages per partner ID
    private var cache: [Int: [APIService.DirectMessageResponse]] = [:]
    /// Cached images per message ID
    private var imageCache: [Int: UIImage] = [:]
    private var pendingImages: Set<Int> = []

    func messages(for partnerId: Int) -> [APIService.DirectMessageResponse] {
        cache[partnerId] ?? []
    }

    func setMessages(_ messages: [APIService.DirectMessageResponse], for partnerId: Int) {
        cache[partnerId] = messages
    }

    /// Optimistically insert a sent message for instant display
    func insertOptimistic(partnerId: Int, text: String, senderId: Int, senderName: String,
                          referenceType: String? = nil, referenceId: Int? = nil,
                          referenceTitle: String? = nil, imageData: String? = nil) {
        let msg = APIService.DirectMessageResponse(
            id: Int.max - (cache[partnerId]?.count ?? 0), // temp ID, replaced on next fetch
            sender_id: senderId,
            recipient_id: partnerId,
            sender_name: senderName,
            text: text,
            reference_type: referenceType,
            reference_id: referenceId,
            reference_title: referenceTitle,
            has_image: imageData != nil ? 1 : nil,
            image_data: imageData,
            read_at: nil,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        var msgs = cache[partnerId] ?? []
        msgs.insert(msg, at: 0) // newest first
        cache[partnerId] = msgs
    }

    // MARK: - Image Cache

    func image(for messageId: Int) -> UIImage? {
        imageCache[messageId]
    }

    func fetchImageIfNeeded(messageId: Int, partnerId: Int, api: APIService) {
        guard imageCache[messageId] == nil, !pendingImages.contains(messageId) else { return }
        pendingImages.insert(messageId)
        Task {
            defer { pendingImages.remove(messageId) }
            do {
                let base64 = try await api.fetchMessageImage(partnerId: partnerId, messageId: messageId)
                if let data = Data(base64Encoded: base64), let img = UIImage(data: data) {
                    imageCache[messageId] = img
                }
            } catch {}
        }
    }

    /// Preload conversations so cache is warm
    func preload(api: APIService, userId: Int) {
        Task {
            do {
                let convos = try await api.fetchConversations()
                for convo in convos {
                    if cache[convo.partner_id] == nil {
                        let msgs = try await api.fetchMessages(partnerId: convo.partner_id)
                        cache[convo.partner_id] = msgs
                    }
                }
            } catch {}
        }
    }
}
