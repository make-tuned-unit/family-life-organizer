import Foundation

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

    private(set) var conversationId: Int?

    /// Start a fresh thread, discarding the current one.
    func startNew() {
        conversationId = nil
        messages = []
        errorMessage = nil
    }

    /// Load a past conversation's history so the user can pick up where they left off.
    func resume(conversationId id: Int, api: APIService) async {
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

    func send(_ text: String, api: APIService, source: ConciergeMessageSource = .text) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        messages.append(Message(role: .user, text: trimmed))
        isSending = true
        errorMessage = nil

        // Stream the reply: create the assistant bubble on the first token or
        // action, fill it as deltas arrive, then reconcile to the authoritative
        // reply on done. Each write is published immediately so other tabs refresh.
        var assistantIndex: Int?
        var streamed = ""
        var liveActions: [ConciergeAction] = []
        do {
            for try await event in api.conciergeMessageStream(trimmed, conversationId: conversationId, source: source) {
                switch event {
                case .delta(let token):
                    streamed += token
                    if let i = assistantIndex, messages.indices.contains(i) {
                        messages[i].text = streamed
                    } else {
                        assistantIndex = messages.count
                        messages.append(Message(role: .assistant, text: streamed, actions: liveActions))
                    }
                case .action(let action):
                    liveActions.append(action)
                    if let i = assistantIndex, messages.indices.contains(i) {
                        messages[i].actions = liveActions
                    } else {
                        assistantIndex = messages.count
                        messages.append(Message(role: .assistant, text: streamed, actions: liveActions))
                    }
                    APIService.publishConciergeActions([action])
                case .done(let response):
                    conversationId = response.conversationId
                    if let i = assistantIndex, messages.indices.contains(i) {
                        messages[i].text = response.reply
                        messages[i].actions = response.actions
                    } else {
                        messages.append(Message(role: .assistant, text: response.reply, actions: response.actions))
                    }
                    if liveActions.isEmpty {
                        APIService.publishConciergeActions(response.actions)
                    }
                }
            }
        } catch {
            // Drop an empty placeholder; keep any partial text and surface the error.
            if let i = assistantIndex, messages.indices.contains(i), messages[i].text.isEmpty, messages[i].actions.isEmpty {
                messages.remove(at: i)
            }
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
