import SwiftUI

@MainActor
@Observable
final class MessageCache {
    /// Cached messages per partner ID
    private var cache: [Int: [APIService.DirectMessageResponse]] = [:]
    /// Cached images per message ID
    private var imageCache: [Int: UIImage] = [:]
    private var pendingImages: Set<Int> = []
    /// For each optimistic temp: the newest REAL message id at insert time.
    /// Confirmation only matches rows NEWER than this — otherwise re-sending
    /// "ok" (or any photo, they all share "Sent a photo") would match an old
    /// row and drop the in-flight bubble.
    private var tempBaselines: [Int: Int] = [:]
    /// Monotonic source for optimistic temp ids: decremented on every send so
    /// two in-flight temps can never collide, even if the cache shrinks (partner
    /// deletes a message) between two sends. A count-derived id reused values and
    /// produced duplicate Identifiable ids + corrupted tempBaselines. Stays
    /// at/above `tempIdThreshold` so temps remain distinguishable from real
    /// server rows; wraps back to Int.max long before it could reach the
    /// threshold (1M sends per session is unreachable).
    private var nextTempId = Int.max
    /// One shared formatter: used for BOTH writing temp timestamps and parsing
    /// them back, so the round-trip can never drift (and no per-poll allocs).
    private static let isoFormatter = ISO8601DateFormatter()

    func messages(for partnerId: Int) -> [APIService.DirectMessageResponse] {
        cache[partnerId] ?? []
    }

    /// Drop everything on logout so a second account on the same device
    /// can't see the previous user's cached conversations.
    func clear() {
        cache = [:]
        imageCache = [:]
        pendingImages = []
        tempBaselines = [:]
        nextTempId = Int.max
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
            // Confirmed: a real row NEWER than everything known at insert
            // time matches this temp. (sender_id 0 = unknown-at-insert; match
            // on text alone rather than never confirming and showing doubles.)
            let baseline = tempBaselines[temp.id] ?? 0
            let confirmed = fetched.contains {
                $0.id > baseline
                    && (temp.sender_id == 0 || $0.sender_id == temp.sender_id)
                    && $0.text == temp.text
            }
            if confirmed { tempBaselines[temp.id] = nil; return false }
            // Unconfirmed temps age out after 2 minutes — long enough for a
            // large photo on slow cellular (the send-failure path removes its
            // own temp immediately; this is only a backstop).
            guard let createdAt = temp.created_at,
                  let created = Self.isoFormatter.date(from: createdAt) else { return false }
            if Date().timeIntervalSince(created) >= 120 { tempBaselines[temp.id] = nil; return false }
            return true
        }
        // Keep only older real pages; the newest window comes from `fetched`
        // (which is authoritative and contiguous by id). An empty fetch keeps
        // all real history (minFetchedId = Int.max).
        let minFetchedId = fetched.map(\.id).min() ?? Int.max
        let olderRetained = existing.filter { $0.id < minFetchedId && $0.id < Self.tempIdThreshold }
        cache[partnerId] = (keptTemps + fetched + olderRetained).sorted { $0.id > $1.id }
    }

    /// Remove the optimistic temp for a failed send so the bubble doesn't lie.
    func removeOptimistic(partnerId: Int, text: String) {
        var msgs = cache[partnerId] ?? []
        if let idx = msgs.firstIndex(where: { $0.id >= Self.tempIdThreshold && $0.text == text }) {
            tempBaselines[msgs[idx].id] = nil
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
        let tempId = nextTempId
        nextTempId -= 1
        if nextTempId < Self.tempIdThreshold { nextTempId = Int.max }
        let msg = APIService.DirectMessageResponse(
            id: tempId, // monotonic temp ID (never reused), replaced on next fetch
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
            created_at: Self.isoFormatter.string(from: Date())
        )
        var msgs = cache[partnerId] ?? []
        // Only rows newer than this can confirm the temp (see mergeNewest).
        tempBaselines[msg.id] = msgs.first(where: { $0.id < Self.tempIdThreshold })?.id ?? 0
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
                    NotificationService.shared.checkForNewMessages(convos, currentUserId: userId)
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
