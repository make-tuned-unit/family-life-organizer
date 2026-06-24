import SwiftUI

/// Conversational concierge — talk to your butler, who can read your data and
/// take actions (add events/tasks/groceries, check budget, etc.) via the backend.
struct ConciergeChatView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    var initialPrompt: String? = nil

    @State private var viewModel = ConciergeChatViewModel()
    @State private var draft = ""
    @State private var showingHistory = false
    @FocusState private var inputFocused: Bool

    private let suggestions = ["What's on today?", "Add a task", "How's our budget?", "What's expiring soon?"]
    private let accent = AccentTheme.saffron.color

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(style: .home)

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if viewModel.messages.isEmpty && !viewModel.isLoading { emptyState }
                                ForEach(viewModel.messages) { message in
                                    messageRow(message).id(message.id)
                                }
                                if viewModel.isSending || viewModel.isLoading { typingIndicator.id("typing") }
                                if let error = viewModel.errorMessage { errorRow(error) }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: viewModel.messages.count) { scrollToBottom(proxy) }
                        .onChange(of: viewModel.isSending) { scrollToBottom(proxy) }
                    }

                    inputBar
                }
            }
            .navigationTitle("Concierge")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if draft.isEmpty, let initialPrompt, !initialPrompt.isEmpty { draft = initialPrompt }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button { viewModel.startNew(); draft = "" } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ConciergeHistoryView(currentId: viewModel.conversationId) { id in
                    showingHistory = false
                    Task { await viewModel.resume(conversationId: id, api: api) }
                }
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageRow(_ message: ConciergeChatViewModel.Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(WarmPalette.ink1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 24)
                }
                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.actions, id: \.self) { action in
                            Label(action.summary, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AccentTheme.sage.color)
                        }
                    }
                    .padding(.leading, 38)
                }
            }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.15), in: Circle())
            ProgressView().tint(accent)
            Spacer()
        }
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 13))
            .foregroundStyle(AccentTheme.terracotta.color)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
                Text("How can I help?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Text("Ask me to add events or tasks, check your budget, plan dinner, and more.")
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink3)
            }
            FlowChips(items: suggestions) { suggestion in
                draft = suggestion
                Task { await submit() }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message your concierge…", text: $draft, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(WarmPalette.cardSurface, in: Capsule())
                .onSubmit { Task { await submit() } }

            Button {
                Task { await submit() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? accent : WarmPalette.ink3.opacity(0.4), in: Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    private func submit() async {
        let text = draft
        draft = ""
        await viewModel.send(text, api: api)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if viewModel.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

/// Simple wrapping row of tappable suggestion chips.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WarmPalette.ink1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WarmPalette.cardSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    ConciergeChatView()
        .environment(APIService())
}
