import SwiftUI

/// Conversational concierge — talk to your butler, who can read your data and
/// take actions (add events/tasks/groceries, check budget, etc.) via the backend.
struct ConciergeChatView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var initialPrompt: String? = nil
    /// When true, the composer opens straight into voice dictation (long-press launch).
    var autoListen: Bool = false
    /// When true, `initialPrompt` is sent immediately (chat-bubble handoff).
    var autoSend: Bool = false

    @State private var viewModel = ConciergeChatViewModel()
    @State private var speech = ConciergeSpeechRecognizer()
    @State private var draft = ""
    @State private var micBase = ""
    @State private var didAutoListen = false
    @State private var didAutoSend = false
    @State private var draftFromVoice = false
    @State private var showingHistory = false
    @State private var activeWorkflow: NativeWorkflow?
    @State private var followsReply = true
    @FocusState private var inputFocused: Bool

    private let suggestions = ["What's on today?", "Add a task", "How's our budget?", "What's expiring soon?"]
    private let accent = KinrowsBrand.evergreen

    var body: some View {
        NavigationStack {
            ZStack {
                KinrowsBrand.oat.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if viewModel.messages.isEmpty && !viewModel.isLoading { emptyState }
                                ForEach(viewModel.messages) { message in
                                    messageRow(message).id(message.id)
                                }
                                if viewModel.isLoading || (viewModel.isSending && viewModel.messages.last?.role != .assistant) { typingIndicator }
                                Color.clear.frame(height: 1).id("bottom")
                                if let error = viewModel.errorMessage { errorRow(error) }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: viewModel.messages.count) { scrollToBottom(proxy) }
                        .onChange(of: viewModel.isSending) { scrollToBottom(proxy) }
                        .onChange(of: viewModel.messages.last?.text) {
                            if followsReply { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .simultaneousGesture(DragGesture().onChanged { _ in followsReply = false })
                        .overlay(alignment: .bottomTrailing) {
                            if !followsReply {
                                Button("Latest", systemImage: "arrow.down") {
                                    followsReply = true
                                    scrollToBottom(proxy)
                                }
                                .font(.flFootnote)
                                .padding(10)
                                .background(KinrowsBrand.mist, in: Capsule())
                                .padding(12)
                            }
                        }
                    }

                    inputBar
                }
            }
            .tint(accent)
            .navigationTitle("Concierge")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !autoSend, draft.isEmpty, let initialPrompt, !initialPrompt.isEmpty { draft = initialPrompt }
            }
            .task {
                var names: [String] = []
                if let people = try? await api.fetchPeople() {
                    names.append(contentsOf: people.map(\.name))
                }
                if let lists = try? await api.fetchLists() {
                    names.append(contentsOf: lists.map(\.name))
                }
                speech.setContextualStrings(names)
                if autoSend, let initialPrompt, !initialPrompt.isEmpty, !didAutoSend {
                    didAutoSend = true
                    await viewModel.send(initialPrompt, api: api, source: .chatExtract, reduceMotion: reduceMotion)
                    return
                }
                // Long-press launch: jump straight into listening so the user can
                // speak a command without tapping into the chat first.
                guard autoListen, !didAutoListen else { return }
                didAutoListen = true
                micBase = draft.isEmpty ? "" : draft.trimmingCharacters(in: .whitespaces) + " "
                inputFocused = false
                draftFromVoice = true
                await speech.start(detectSilence: true, onSilence: {
                    Task { _ = await speech.finish() }
                }, onUpdate: { transcript in draft = micBase + transcript })
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Conversation history")
                    .help("Conversation history")
                    .disabled(viewModel.isSending || viewModel.isLoading)
                    Button { viewModel.startNew(); draft = "" } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                    .help("New conversation")
                    .disabled(viewModel.messages.isEmpty || viewModel.isSending || viewModel.isLoading)
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
            .sheet(item: $activeWorkflow) { workflow in
                workflowDestination(workflow)
            }
            .onDisappear { speech.stop() }
        }
    }

    private enum NativeWorkflow: String, Identifiable {
        case receipt, cook, calendar, trips, health, groups, messages, notes, routines, history
        var id: String { rawValue }
    }

    @ViewBuilder
    private func workflowDestination(_ workflow: NativeWorkflow) -> some View {
        switch workflow {
        case .receipt:
            ReceiptScannerView(onReceiptSaved: {
                NotificationCenter.default.post(name: APIService.conciergeDataDidChange, object: nil)
            })
        case .messages: ChatSheet()
        default:
            NavigationStack {
                Group {
                    switch workflow {
                    case .cook: CookView()
                    case .calendar: CalendarView()
                    case .trips: TripsView()
                    case .health: RivalriesView()
                    case .groups: FamilyGroupsView()
                    case .notes: NotesView()
                    case .routines: RoutinesView()
                    default: EmptyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { activeWorkflow = nil }
                    }
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
                    .font(.flBody)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    RowanMotionView(pose: .idleSmile, loops: true,
                                    isActive: viewModel.isSending && message.id == viewModel.messages.last?.id,
                                    maxWidth: 36, maxHeight: 42)
                        .frame(width: 36, height: 42)
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.isSending && message.id == viewModel.messages.last?.id {
                            Text(message.text.isEmpty ? "Rowan is working…" : "Rowan is replying…")
                                .font(.flCaption)
                                .foregroundStyle(KinrowsBrand.evergreen)
                        }
                        ConciergeResponseBody(text: message.text)
                    }
                        .font(.flBody)
                        .foregroundStyle(WarmPalette.ink1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            KinrowsIllustration(.mascot(.celebrating), maxWidth: 22, maxHeight: 22)
                            Label(message.actions.contains(where: { $0.tool == "open_workflow" }) ? "Actions and next steps" : "Saved changes", systemImage: "checkmark.circle.fill")
                        }
                        .font(.flFootnote.weight(.bold))
                        ForEach(message.actions, id: \.self) { action in
                            if action.tool == "open_workflow", let value = action.workflow, let workflow = NativeWorkflow(rawValue: value) {
                                Button(action.summary) {
                                    if workflow == .history { showingHistory = true }
                                    else { activeWorkflow = workflow }
                                }
                                .font(.flBody.weight(.semibold))
                                .padding(.vertical, 8)
                            } else {
                                Text(action.summary).font(.flCaption.weight(.medium))
                            }
                        }
                    }
                    .foregroundStyle(KinrowsBrand.evergreen)
                    .padding(.leading, 38)
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    // Rowan thinks while the reply is on its way — the loop replaces the
    // spinner, the text keeps the state readable.
    private var typingIndicator: some View {
        HStack(spacing: 10) {
            RowanMotionView(pose: .thinking, loops: true, maxWidth: 44, maxHeight: 52)
                .frame(width: 44, height: 52)
            Text("Rowan is thinking…")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.flFootnote)
            .foregroundStyle(KinrowsBrand.clayDeep)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                RowanMotionView(pose: .wave, maxWidth: 120, maxHeight: 130)
                    .frame(height: 130)
                Text("How can I help?")
                    .font(.flDisplaySmall)
                    .foregroundStyle(KinrowsBrand.evergreen)
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
                    .background(KinrowsBrand.oatLight, in: RoundedRectangle(cornerRadius: KinrowsBrand.Radius.lg))
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
                .accessibilityLabel("Send message")
                .help("Send message")
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
                    _ = await speech.finish()
                } else {
                    var names: [String] = []
                    if let people = try? await api.fetchPeople() {
                        names.append(contentsOf: people.map(\.name))
                    }
                    if let lists = try? await api.fetchLists() {
                        names.append(contentsOf: lists.map(\.name))
                    }
                    speech.setContextualStrings(names)
                    micBase = draft.isEmpty ? "" : draft.trimmingCharacters(in: .whitespaces) + " "
                    inputFocused = false
                    draftFromVoice = true
                    await speech.start(detectSilence: true, onSilence: {
                        Task { _ = await speech.finish() }
                    }, onUpdate: { transcript in draft = micBase + transcript })
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
        .help(speech.isRecording ? "Stop dictation" : "Dictate a message")
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending && !viewModel.isLoading
    }

    private func submit() async {
        if speech.isRecording {
            let final = await speech.finish()
            draft = micBase + final
        }
        followsReply = true
        let text = draft
        let source: ConciergeMessageSource = draftFromVoice ? .voice : .text
        draft = ""
        draftFromVoice = false
        await viewModel.send(text, api: api, source: source, reduceMotion: reduceMotion)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard followsReply else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

/// Native hanging bullets and inline emphasis stay legible as new words arrive.
struct ConciergeResponseBody: View {
    let text: String

    private struct Block {
        var marker: String?
        var text: String
        var heading = false
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var newParagraph = true
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { newParagraph = true; continue }
            var content = line
            var marker: String?
            let heading = line.hasPrefix("#")
            if ["- ", "* ", "• "].contains(where: line.hasPrefix) {
                marker = "•"
                content = String(line.dropFirst(2))
            } else if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                marker = String(line[range]).trimmingCharacters(in: .whitespaces)
                content = String(line[range.upperBound...])
            } else if heading {
                content = String(line.drop(while: { $0 == "#" || $0 == " " }))
            }
            if !newParagraph, marker == nil, !heading, let last = result.indices.last,
               !result[last].heading {
                result[last].text += " " + content
            } else {
                result.append(Block(marker: marker, text: content, heading: heading))
            }
            newParagraph = false
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let marker = block.marker {
                        Text(marker)
                            .foregroundStyle(KinrowsBrand.evergreen)
                            .frame(minWidth: 12, alignment: .leading)
                    }
                    Text((try? AttributedString(markdown: block.text,
                         options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text))
                        .font(block.heading ? .flHeadline : .flBody)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
        .tint(KinrowsBrand.riverDeep)
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
                        .background(KinrowsBrand.oatLight, in: RoundedRectangle(cornerRadius: KinrowsBrand.Radius.lg))
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
