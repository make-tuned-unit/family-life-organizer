import SwiftUI
import PhotosUI

struct ConversationView: View {
    let partnerId: Int
    let partnerName: String
    var quotedItem: QuotedItem?

    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(ProfileImageCache.self) private var profileCache
    @Environment(MessageCache.self) private var messageCache

    @State private var newMessage = ""
    @State private var isSending = false
    @State private var pendingQuote: QuotedItem?
    @State private var pollTimer: Timer?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var showingNewDecision = false
    @State private var openDecisions: [DecisionResponse] = []
    @State private var fullscreenImage: UIImage?
    @State private var isLoadingOlder = false
    @State private var reachedOldEnd = false
    private let messagePageSize = 50

    private var messages: [APIService.DirectMessageResponse] {
        messageCache.messages(for: partnerId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Open decisions bar
            if !openDecisions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(openDecisions) { decision in
                            NavigationLink {
                                DecisionDetailView(decision: decision)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 10))
                                    Text(decision.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(TabAccent.decisions.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(TabAccent.decisions.color.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.vertical, 6)
                .background(WarmPalette.cardSurface.opacity(0.8))
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if isLoadingOlder {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                        ForEach(messages.reversed()) { msg in
                            MessageBubble(
                                message: msg,
                                partnerId: partnerId,
                                isOwn: msg.sender_id == auth.currentUser?.id,
                                onImageTap: { image in fullscreenImage = image }
                            )
                            .id(msg.id)
                            .onAppear {
                                // Top of the thread (oldest loaded) reached → page older.
                                if msg.id == messages.last?.id {
                                    Task { await loadOlderMessages(proxy: proxy) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                // Scroll to bottom only when the NEWEST message changes (sent or
                // received) — not when older pages are prepended.
                .onChange(of: messages.first?.id) {
                    if let newest = messages.first {
                        withAnimation { proxy.scrollTo(newest.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Compose bar
            VStack(spacing: 0) {
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

                if let imageData = pendingImageData, let uiImage = UIImage(data: imageData) {
                    HStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button { pendingImageData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(WarmPalette.ink4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .onChange(of: selectedPhoto) {
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                pendingImageData = UIImage(data: data)?.jpegData(compressionQuality: 0.5)
                            }
                        }
                    }

                    Button { showingNewDecision = true } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TabAccent.decisions.color)
                    }

                    TextField("Message...", text: $newMessage)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend ? TabAccent.home.color : WarmPalette.ink4)
                    }
                    .disabled(!canSend || isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle(partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewDecision) {
            NewDecisionView { await loadDecisions() }
        }
        .fullScreenCover(item: Binding(
            get: { fullscreenImage.map { IdentifiableImage(image: $0) } },
            set: { fullscreenImage = $0?.image }
        )) { item in
            ImagePreviewView(image: item.image) { fullscreenImage = nil }
        }
        .task {
            pendingQuote = quotedItem
            // Show cached messages instantly, then refresh from server
            await refreshMessages()
            await loadDecisions()
            try? await api.markMessagesRead(partnerId: partnerId)
        }
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in
                    await refreshMessages()
                    try? await api.markMessagesRead(partnerId: partnerId)
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespaces).isEmpty || pendingImageData != nil
    }

    private func refreshMessages() async {
        do {
            let fetched = try await api.fetchMessages(partnerId: partnerId, limit: messagePageSize)
            messageCache.mergeNewest(fetched, for: partnerId)
        } catch {}
    }

    // Cursor pagination: load older messages using the oldest loaded id as the
    // before_id cursor, then restore scroll position to where the user was.
    private func loadOlderMessages(proxy: ScrollViewProxy) async {
        guard !isLoadingOlder, !reachedOldEnd else { return }
        guard let oldestId = messages.last?.id, oldestId < MessageCache.tempIdThreshold else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let older = try await api.fetchMessages(partnerId: partnerId, limit: messagePageSize, beforeId: oldestId)
            guard !older.isEmpty else { reachedOldEnd = true; return }
            messageCache.appendOlder(older, for: partnerId)
            if older.count < messagePageSize { reachedOldEnd = true }
            // Keep the viewport anchored on the message that was at the top.
            proxy.scrollTo(oldestId, anchor: .top)
        } catch {}
    }

    private func loadDecisions() async {
        do {
            // Only show decisions referenced in this conversation's messages
            let referencedIds = Set(
                messages.compactMap { msg -> Int? in
                    guard msg.reference_type == "decision" || msg.reference_type == "poll" else { return nil }
                    return msg.reference_id
                }
            )
            guard !referencedIds.isEmpty else {
                openDecisions = []
                return
            }
            let all = try await api.fetchDecisions()
            let now = Date()
            openDecisions = all.filter { decision in
                referencedIds.contains(decision.id)
                && decision.status == DecisionStatus.active.rawValue
                && !isExpired(decision, now: now)
            }
        } catch {}
    }

    private func isExpired(_ decision: DecisionResponse, now: Date) -> Bool {
        guard let expiresStr = decision.expires_at,
              let expiresDate = ISO8601DateFormatter.flexible.date(from: expiresStr) else {
            return false
        }
        return expiresDate <= now
    }

    private func send() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || pendingImageData != nil else { return }
        isSending = true
        let quote = pendingQuote
        let imageBase64 = pendingImageData?.base64EncodedString()

        // Optimistic insert — show message immediately
        messageCache.insertOptimistic(
            partnerId: partnerId,
            text: text.isEmpty ? "Sent a photo" : text,
            senderId: auth.currentUser?.id ?? 0,
            senderName: auth.currentUser?.name ?? "Me",
            referenceType: quote?.type,
            referenceId: quote?.id,
            referenceTitle: quote?.title,
            imageData: imageBase64
        )
        let sentText = text.isEmpty ? "Sent a photo" : text
        newMessage = ""
        pendingQuote = nil
        pendingImageData = nil
        selectedPhoto = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                _ = try await api.sendMessage(
                    recipientId: partnerId,
                    text: sentText,
                    referenceType: quote?.type,
                    referenceId: quote?.id,
                    referenceTitle: quote?.title,
                    imageData: imageBase64
                )
                // Replace optimistic with server data
                await refreshMessages()
            } catch {}
            isSending = false
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: APIService.DirectMessageResponse
    let partnerId: Int
    let isOwn: Bool
    var onImageTap: ((UIImage) -> Void)?

    @Environment(APIService.self) private var api
    @Environment(MessageCache.self) private var messageCache

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if let type = message.reference_type, let title = message.reference_title {
                    QuotedItemCard(type: type, title: title)
                }

                // Image — from local cache or lazy-loaded
                if let localImage = message.image_data.flatMap({ Data(base64Encoded: $0) }).flatMap({ UIImage(data: $0) }) {
                    Button { onImageTap?(localImage) } label: {
                        Image(uiImage: localImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if message.has_image == 1 {
                    if let cached = messageCache.image(for: message.id) {
                        Button { onImageTap?(cached) } label: {
                            Image(uiImage: cached)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(WarmPalette.ink1.opacity(0.06))
                            .frame(width: 150, height: 100)
                            .overlay {
                                ProgressView()
                                    .tint(WarmPalette.ink3)
                            }
                            .onAppear {
                                messageCache.fetchImageIfNeeded(messageId: message.id, partnerId: partnerId, api: api)
                            }
                    }
                }

                if message.text != "Sent a photo" || (message.has_image != 1 && message.image_data == nil) {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(isOwn ? .white : WarmPalette.ink1)
                }

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

// MARK: - Fullscreen Image Preview

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ImagePreviewView: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = value.magnification }
                        .onEnded { _ in withAnimation { scale = max(1, scale) } }
                )

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(16)
            }
        }
        .statusBarHidden()
    }
}
