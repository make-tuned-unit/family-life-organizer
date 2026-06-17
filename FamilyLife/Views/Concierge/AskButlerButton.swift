import SwiftUI

/// App-wide channel for requesting the concierge chat with a seeded prompt.
/// Feature views call `ask(_:)`; MainTabView switches to the Concierge tab and
/// ConciergeView presents the chat (or the paywall, if not premium).
@Observable
final class ConciergeLaunch {
    var requestedPrompt: String?

    func ask(_ prompt: String) { requestedPrompt = prompt }

    /// Read and clear the pending prompt.
    func consume() -> String? {
        defer { requestedPrompt = nil }
        return requestedPrompt
    }
}

/// A small toolbar entry that hands a contextual prompt to the concierge.
struct AskButlerButton: View {
    @Environment(ConciergeLaunch.self) private var launch
    let prompt: String

    var body: some View {
        Button { launch.ask(prompt) } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AccentTheme.saffron.color)
        }
        .accessibilityLabel("Ask your concierge")
    }
}
