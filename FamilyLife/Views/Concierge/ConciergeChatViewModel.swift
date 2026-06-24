import Foundation

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

    func send(_ text: String, api: APIService) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        messages.append(Message(role: .user, text: trimmed))
        isSending = true
        errorMessage = nil

        do {
            let response = try await api.sendConciergeMessage(trimmed, conversationId: conversationId)
            conversationId = response.conversationId
            messages.append(Message(role: .assistant, text: response.reply, actions: response.actions))
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
