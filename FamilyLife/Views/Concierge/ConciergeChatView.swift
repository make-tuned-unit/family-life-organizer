import SwiftUI

/// Conversational concierge — talk to your butler, who can read your data and
/// take actions (add events/tasks/groceries, check budget, etc.) via the backend.
struct ConciergeChatView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    var initialPrompt: String? = nil
    /// When true, the composer opens straight into voice dictation (long-press launch).
    var autoListen: Bool = false

    @State private var viewModel = ConciergeChatViewModel()
    @State private var speech = ConciergeSpeechRecognizer()
    @State private var draft = ""
    @State private var micBase = ""
    @State private var didAutoListen = false
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
            .task {
                // Long-press launch: jump straight into listening so the user can
                // speak a command without tapping into the chat first.
                guard autoListen, !didAutoListen else { return }
                didAutoListen = true
                micBase = draft.isEmpty ? "" : draft.trimmingCharacters(in: .whitespaces) + " "
                inputFocused = false
                await speech.start { transcript in draft = micBase + transcript }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Conversation history")
                    Button { viewModel.startNew(); draft = "" } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
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
            .onDisappear { speech.stop() }
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
                    .font(.flBody)
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
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(message.text)
                        .font(.flBody)
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
                                .font(.flCaption.weight(.medium))
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
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.15), in: Circle())
            ProgressView().tint(accent)
            Spacer()
        }
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.flFootnote)
            .foregroundStyle(AccentTheme.terracotta.color)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
                Text("How can I help?")
                    .font(.flTitle)
                    .foregroundStyle(WarmPalette.ink1)
                Text("Ask me to add events or tasks, check your budget, plan dinner, and more.")
                    .font(.flSubheadline)
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
        VStack(spacing: 6) {
            if let err = speech.errorMessage {
                Text(err)
                    .font(.flCaption)
                    .foregroundStyle(WarmPalette.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                micButton

                TextField(speech.isRecording ? "Listening…" : "Message your concierge…", text: $draft, axis: .vertical)
                    .font(.flBody)
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
                        .accessibilityLabel("Send message")
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // Hold-free toggle: tap to start dictation, tap again to stop. The live
    // transcript streams into the composer (appended after any typed text), so
    // the user can review or edit before sending.
    private var micButton: some View {
        Button {
            Task {
                if speech.isRecording {
                    speech.stop()
                } else {
                    micBase = draft.isEmpty ? "" : draft.trimmingCharacters(in: .whitespaces) + " "
                    inputFocused = false
                    await speech.start { transcript in draft = micBase + transcript }
                }
            }
        } label: {
            Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(speech.isRecording ? .white : accent)
                .frame(width: 40, height: 40)
                .background(speech.isRecording ? WarmPalette.bad : WarmPalette.cardSurface, in: Circle())
                .animation(.easeInOut(duration: 0.2), value: speech.isRecording)
        }
        .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate a message")
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    private func submit() async {
        if speech.isRecording { speech.stop() }
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
                        .font(.flSubheadline.weight(.medium))
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
