import SwiftUI
import PhotosUI

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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var showingNewDecision = false
    @State private var openDecisions: [DecisionResponse] = []
    @State private var fullscreenImage: UIImage?

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
                        ForEach(messages.reversed()) { msg in
                            MessageBubble(
                                message: msg,
                                isOwn: msg.sender_id == auth.currentUser?.id,
                                onImageTap: { image in fullscreenImage = image }
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

                // Image preview
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
                    // Photo picker
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

                    // Decision button
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
            NewDecisionView {
                await loadDecisions()
            }
        }
        .fullScreenCover(item: Binding(
            get: { fullscreenImage.map { IdentifiableImage(image: $0) } },
            set: { fullscreenImage = $0?.image }
        )) { item in
            ImagePreviewView(image: item.image) {
                fullscreenImage = nil
            }
        }
        .task {
            pendingQuote = quotedItem
            await loadMessages()
            await loadDecisions()
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

    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespaces).isEmpty || pendingImageData != nil
    }

    private func loadMessages() async {
        do {
            messages = try await api.fetchMessages(partnerId: partnerId)
        } catch {}
    }

    private func loadDecisions() async {
        do {
            let all = try await api.fetchDecisions()
            openDecisions = all.filter { $0.status == DecisionStatus.active.rawValue }
        } catch {}
    }

    private func send() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || pendingImageData != nil else { return }
        isSending = true
        let quote = pendingQuote
        let imageBase64 = pendingImageData?.base64EncodedString()
        Task {
            do {
                _ = try await api.sendMessage(
                    recipientId: partnerId,
                    text: text.isEmpty ? "Sent a photo" : text,
                    referenceType: quote?.type,
                    referenceId: quote?.id,
                    referenceTitle: quote?.title,
                    imageData: imageBase64
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                newMessage = ""
                pendingQuote = nil
                pendingImageData = nil
                selectedPhoto = nil
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
    var onImageTap: ((UIImage) -> Void)?

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                // Quoted reference
                if let type = message.reference_type, let title = message.reference_title {
                    QuotedItemCard(type: type, title: title)
                }

                // Image
                if let base64 = message.image_data,
                   let data = Data(base64Encoded: base64),
                   let uiImage = UIImage(data: data) {
                    Button { onImageTap?(uiImage) } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if message.text != "Sent a photo" || message.image_data == nil {
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
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
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
