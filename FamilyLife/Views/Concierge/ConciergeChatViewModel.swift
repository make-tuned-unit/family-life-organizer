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
    var errorMessage: String?

    private var conversationId: Int?

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
