import Foundation
import Observation

@MainActor
@Observable
final class ConciergeChatViewModel {
    /// A message in the visible thread.
    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var actions: [ConciergeAction] = []
    }

    private(set) var messages: [Message] = []
    private(set) var isSending = false
    private(set) var isLoading = false
    var errorMessage: String?

    private var pendingReply = ""
    private var replyID: UUID?
    private var reduceReplyMotion = false

    private(set) var conversationId: Int?

    /// Start a fresh thread, discarding the current one.
    func startNew() {
        guard !isSending, !isLoading else { return }
        conversationId = nil
        messages = []
        errorMessage = nil
    }

    /// Load a past conversation's history so the user can pick up where they left off.
    func resume(conversationId id: Int, api: APIService) async {
        guard !isSending, !isLoading else { return }
        conversationId = id
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let history = try await api.fetchConciergeMessages(conversationId: id)
            messages = history.map { Message(role: $0.role == "user" ? .user : .assistant, text: $0.content) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ text: String, api: APIService, source: ConciergeMessageSource = .text, reduceMotion: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending, !isLoading else { return }

        messages.append(Message(role: .user, text: trimmed))
        isSending = true
        errorMessage = nil

        // Stream the reply: create the assistant bubble on the first token or
        // action, fill it as deltas arrive, then reconcile to the authoritative
        // reply on done. Each write is published immediately so other tabs refresh.
        reduceReplyMotion = reduceMotion
        pendingReply = ""
        replyID = nil
        let revealTask = Task { @MainActor in
            while !Task.isCancelled {
                revealNextWords()
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
        defer { revealTask.cancel(); replyID = nil; isSending = false }
        var assistantIndex: Int?
        var streamed = ""
        var liveActions: [ConciergeAction] = []
        do {
            for try await event in api.conciergeMessageStream(trimmed, conversationId: conversationId, source: source) {
                switch event {
                case .delta(let token):
                    streamed += token
                    if let i = assistantIndex, messages.indices.contains(i) {
                        pendingReply = streamed
                    } else {
                        assistantIndex = messages.count
                        messages.append(Message(role: .assistant, text: "", actions: liveActions))
                        replyID = messages.last?.id
                        pendingReply = streamed
                    }
                case .action(let action):
                    liveActions.append(action)
                    if let i = assistantIndex, messages.indices.contains(i) {
                        messages[i].actions = liveActions
                    } else {
                        assistantIndex = messages.count
                        messages.append(Message(role: .assistant, text: "", actions: liveActions))
                        replyID = messages.last?.id
                        pendingReply = streamed
                    }
                    APIService.publishConciergeActions([action])
                case .done(let response):
                    conversationId = response.conversationId
                    if let i = assistantIndex, messages.indices.contains(i) {
                        pendingReply = response.reply
                        messages[i].actions = response.actions
                    } else {
                        messages.append(Message(role: .assistant, text: "", actions: response.actions))
                        replyID = messages.last?.id
                        pendingReply = response.reply
                    }
                    if liveActions.isEmpty {
                        APIService.publishConciergeActions(response.actions)
                    }
                }
            }
            // Keep receiving network events independently of the visual cadence.
            while let id = replyID, let message = messages.first(where: { $0.id == id }),
                  message.text != pendingReply {
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if let i = assistantIndex, messages.indices.contains(i) {
                messages[i].text = pendingReply
            }
            // Drop an empty placeholder; keep any partial text and surface the error.
            if let i = assistantIndex, messages.indices.contains(i), messages[i].text.isEmpty, messages[i].actions.isEmpty {
                messages.remove(at: i)
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Reveal whole words at a steady cadence, catching up gently on large bursts.
    private func revealNextWords() {
        guard let id = replyID, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let shown = messages[index].text
        guard shown != pendingReply else { return }
        if reduceReplyMotion {
            messages[index].text = pendingReply
            return
        }
        // The final server reply excludes intermediate tool-call narration.
        let prefix = pendingReply.hasPrefix(shown) ? shown : ""
        let remaining = pendingReply.dropFirst(prefix.count)
        let step = remaining.count > 900 ? 28 : 12
        var end = remaining.index(remaining.startIndex, offsetBy: min(step, remaining.count))
        while end < remaining.endIndex, !remaining[end].isWhitespace {
            end = remaining.index(after: end)
        }
        messages[index].text = prefix + remaining[..<end]
    }
}
