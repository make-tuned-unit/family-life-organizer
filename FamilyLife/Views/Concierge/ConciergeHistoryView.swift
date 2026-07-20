import SwiftUI

/// Lists the user's past concierge conversations so they can resume one with its
/// full context. Selecting a row hands the conversation id back to the chat view.
struct ConciergeHistoryView: View {
    var currentId: Int?
    var onSelect: (Int) -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var conversations: [ConciergeConversationSummary] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private let accent = AccentTheme.saffron.color

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(style: .home)

                if loading {
                    FLLoadingState(message: "Loading your conversations…")
                } else if let errorMessage {
                    WarmEmptyState(title: "Couldn't load", systemImage: "exclamationmark.triangle", description: errorMessage)
                } else if conversations.isEmpty {
                    WarmEmptyState(title: "No conversations yet", systemImage: "sparkles", description: "Your past chats with the concierge will appear here.")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(conversations.enumerated()), id: \.element.id) { index, convo in
                                if index > 0 { GlassDivider() }
                                row(convo)
                            }
                        }
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func row(_ convo: ConciergeConversationSummary) -> some View {
        Button { onSelect(convo.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(convo.displayTitle)
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink1)
                        .lineLimit(1)
                    if let last = convo.lastMessage, !last.isEmpty {
                        Text(last)
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if convo.id == currentId {
                    Text("Current")
                        .font(.flOverline)
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(convo.id == currentId)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            conversations = try await api.fetchConciergeConversations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ConciergeHistoryView(currentId: nil) { _ in }
        .environment(APIService())
}
