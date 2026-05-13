import SwiftUI

struct ConversationView: View {
    let partnerId: Int
    let partnerName: String
    var quotedItem: QuotedItem?

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(ProfileImageCache.self) private var profileCache

    @State private var messages: [APIService.DirectMessageResponse] = []
    @State private var newMessage = ""
    @State private var isSending = false
    @State private var pendingQuote: QuotedItem?
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages.reversed()) { msg in
                            MessageBubble(
                                message: msg,
                                isOwn: msg.sender_id == auth.currentUser?.id
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) {
                    if let last = messages.reversed().last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Compose bar
            VStack(spacing: 0) {
                // Quoted item preview
                if let quote = pendingQuote {
                    HStack {
                        QuotedItemCard(type: quote.type, title: quote.title)
                        Spacer()
                        Button { pendingQuote = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                HStack(spacing: 10) {
                    TextField("Message...", text: $newMessage)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(newMessage.isEmpty ? WarmPalette.ink4 : TabAccent.home.color)
                    }
                    .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle(partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            pendingQuote = quotedItem
            await loadMessages()
            try? await api.markMessagesRead(partnerId: partnerId)
        }
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in
                    await loadMessages()
                    try? await api.markMessagesRead(partnerId: partnerId)
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func loadMessages() async {
        do {
            messages = try await api.fetchMessages(partnerId: partnerId)
        } catch {}
    }

    private func send() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSending = true
        let quote = pendingQuote
        Task {
            do {
                _ = try await api.sendMessage(
                    recipientId: partnerId,
                    text: text,
                    referenceType: quote?.type,
                    referenceId: quote?.id,
                    referenceTitle: quote?.title
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                newMessage = ""
                pendingQuote = nil
                await loadMessages()
            } catch {}
            isSending = false
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: APIService.DirectMessageResponse
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                // Quoted reference
                if let type = message.reference_type, let title = message.reference_title {
                    QuotedItemCard(type: type, title: title)
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(isOwn ? .white : WarmPalette.ink1)

                if let date = message.created_at {
                    Text(relativeTime(date))
                        .font(.system(size: 10))
                        .foregroundStyle(isOwn ? .white.opacity(0.7) : WarmPalette.ink4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isOwn ? AnyShapeStyle(TabAccent.home.color) : AnyShapeStyle(WarmPalette.cardSurface),
                in: RoundedRectangle(cornerRadius: 16)
            )

            if !isOwn { Spacer(minLength: 60) }
        }
    }

    private func relativeTime(_ dateStr: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}
