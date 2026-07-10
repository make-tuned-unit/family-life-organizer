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

    /// Drop everything on logout so a second account on the same device
    /// can't see the previous user's cached conversations.
    func clear() {
        cache = [:]
        imageCache = [:]
        pendingImages = []
    }

    func setMessages(_ messages: [APIService.DirectMessageResponse], for partnerId: Int) {
        cache[partnerId] = messages
    }

    /// Optimistic temp messages use ids near Int.max (see insertOptimistic).
    /// Anything at/above this is a temp, not a real server row.
    static let tempIdThreshold = Int.max - 1_000_000

    /// Merge the newest page (server-authoritative for its id window) into the
    /// cache WITHOUT discarding older pages already loaded via load-older.
    /// Refreshes read receipts in the newest window. Optimistic temps are kept
    /// until their real row arrives (or they age out) — dropping them on every
    /// poll made an in-flight send vanish and reappear, and made a FAILED send
    /// vanish forever with no feedback.
    func mergeNewest(_ fetched: [APIService.DirectMessageResponse], for partnerId: Int) {
        let existing = cache[partnerId] ?? []
        let temps = existing.filter { $0.id >= Self.tempIdThreshold }
        let keptTemps = temps.filter { temp in
            // Confirmed: its real row is in the fetched window now.
            let confirmed = fetched.contains { $0.sender_id == temp.sender_id && $0.text == temp.text }
            if confirmed { return false }
            // Unconfirmed temps age out after 30s (the send failure path
            // removes its own temp immediately; this is just a backstop).
            guard let createdAt = temp.created_at,
                  let created = ISO8601DateFormatter().date(from: createdAt) else { return false }
            return Date().timeIntervalSince(created) < 30
        }
        guard let minFetchedId = fetched.map(\.id).min() else {
            cache[partnerId] = keptTemps + existing.filter { $0.id < Self.tempIdThreshold }
            return
        }
        // Keep only older real pages; the newest window comes from `fetched`
        // (which is authoritative and contiguous by id).
        let olderRetained = existing.filter { $0.id < minFetchedId && $0.id < Self.tempIdThreshold }
        cache[partnerId] = (keptTemps + fetched + olderRetained).sorted { $0.id > $1.id }
    }

    /// Remove the optimistic temp for a failed send so the bubble doesn't lie.
    func removeOptimistic(partnerId: Int, text: String) {
        var msgs = cache[partnerId] ?? []
        if let idx = msgs.firstIndex(where: { $0.id >= Self.tempIdThreshold && $0.text == text }) {
            msgs.remove(at: idx)
            cache[partnerId] = msgs
        }
    }

    /// Merge an older page (load-older) into the cache, deduping by id.
    func appendOlder(_ fetched: [APIService.DirectMessageResponse], for partnerId: Int) {
        var byId: [Int: APIService.DirectMessageResponse] = [:]
        for m in cache[partnerId] ?? [] { byId[m.id] = m }
        for m in fetched { byId[m.id] = m }
        cache[partnerId] = byId.values.sorted { $0.id > $1.id }
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

    /// Preload conversations so cache is warm + check for new message notifications
    func preload(api: APIService, userId: Int) {
        Task {
            do {
                let convos = try await api.fetchConversations()

                // Fire notifications for new messages
                if await NotificationService.shared.isAuthorized() {
                    NotificationService.shared.checkForNewMessages(convos)
                }

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
