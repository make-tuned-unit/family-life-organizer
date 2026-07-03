import SwiftUI

// MARK: - Incoming Coverage Requests (helper's view)
// Shows coverage requests where the current user has been asked to help.
// Allows approve/decline from within the app — no browser link needed.

struct IncomingCoverageView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var requests: [APIService.IncomingCoverageRequest] = []
    @State private var isLoading = false
    @State private var selectedRequest: APIService.IncomingCoverageRequest?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("INCOMING REQUESTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color).tracking(0.4)
                    Text("Help requests")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Families have asked for your help with these time slots.")
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18)

                if isLoading && requests.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if requests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("No pending requests")
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink3)
                        Text("When someone asks for your help, it will appear here.")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink4)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(requests) { request in
                            IncomingRequestCard(request: request) {
                                selectedRequest = request
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .care) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .refreshable { await loadRequests() }
        .task { await loadRequests() }
        .sheet(item: $selectedRequest) { request in
            NavigationStack {
                ApproveRequestSheet(request: request) {
                    await loadRequests()
                }
            }
        }
    }

    private func loadRequests() async {
        isLoading = true
        requests = (try? await api.fetchIncomingCoverage()) ?? []
        isLoading = false
    }
}

// MARK: - Incoming Request Card

struct IncomingRequestCard: View {
    let request: APIService.IncomingCoverageRequest
    let onApprove: () -> Void

    private var reasonIcon: String {
        switch request.reason {
        case "Watch the kids": "figure.and.child.holdinghands"
        case "Watch the dog": "dog.fill"
        case "Cat care": "cat.fill"
        case "House sitting": "house.fill"
        case "Plant care": "leaf.fill"
        case "Pet sitting": "pawprint.fill"
        case "Eldercare": "heart.fill"
        default: "hand.raised.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: reasonIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(TabAccent.care.color)
                    .frame(width: 36, height: 36)
                    .background(TabAccent.care.color.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.requester_name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(request.reason)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink2)
                }
                Spacer()

                if request.recipient_status == "approved" {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Approved")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(WarmPalette.good)
                } else {
                    Button(action: onApprove) {
                        Text("Review")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TabAccent.care.color)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(TabAccent.care.color.opacity(0.12), in: Capsule())
                    }
                }
            }

            if let note = request.note, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(.system(size: 13)).italic()
                    .foregroundStyle(WarmPalette.ink3)
            }

            if let date = request.created_at {
                Text(relativeTime(date))
                    .font(.system(size: 11))
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private func relativeTime(_ dateStr: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: dateStr) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Approve Request Sheet

struct ApproveRequestSheet: View {
    let request: APIService.IncomingCoverageRequest
    let onApproved: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [APIService.CoverageWindowResponse] = []
    @State private var selectedWindow: APIService.CoverageWindowResponse?
    @State private var helperNote = ""
    @State private var isSaving = false
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("COVERAGE REQUEST")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color).tracking(0.4)
                    Text("\(request.requester_name) needs help")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Label(request.reason, systemImage: reasonIcon)
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)

                if let note = request.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.system(size: 15)).italic()
                        .foregroundStyle(WarmPalette.ink2)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 22).padding(.bottom, 14)
                }

                // Window selection
                Text("PICK A TIME SLOT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3).tracking(0.4)
                    .padding(.horizontal, 22).padding(.bottom, 8)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(windows) { window in
                            let isSelected = selectedWindow?.id == window.id
                            Button { selectedWindow = window } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friendlyDate(window.window_date))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(WarmPalette.ink1)
                                        Text("\(window.start_time) – \(window.end_time)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(TabAccent.care.color)
                                        if let desc = window.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.system(size: 13))
                                                .foregroundStyle(WarmPalette.ink3)
                                        }
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(TabAccent.care.color)
                                    }
                                }
                                .padding(14)
                                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(isSelected ? TabAccent.care.color.opacity(0.4) : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 14)
                }

                // Note
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD A NOTE (OPTIONAL)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3).tracking(0.4)
                    TextField("e.g. We'll bring lunch!", text: $helperNote)
                        .font(.system(size: 15)).foregroundStyle(WarmPalette.ink2)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 22).padding(.bottom, 18)

                // Approve button
                Button {
                    Task { await approve() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().tint(WarmPalette.cream1)
                        }
                        Text("Confirm availability")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(WarmPalette.cream1).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(WarmPalette.ink1, in: RoundedRectangle(cornerRadius: 22))
                }
                .disabled(selectedWindow == nil || isSaving)
                .opacity(selectedWindow == nil ? 0.5 : 1)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
        .background { AmbientBackground(style: .care) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.foregroundStyle(WarmPalette.ink2)
            }
        }
        .task { await loadWindows() }
    }

    private func loadWindows() async {
        isLoading = true
        if let detail = try? await api.fetchCoverageDetail(id: request.id) {
            windows = detail.windows
        }
        isLoading = false
    }

    private func approve() async {
        guard let window = selectedWindow else { return }
        isSaving = true
        do {
            try await api.approveIncomingCoverage(requestId: request.id, data: [
                "window_id": window.id,
                "approved_date": window.window_date,
                "approved_start": window.start_time,
                "approved_end": window.end_time,
                "helper_note": helperNote.isEmpty ? NSNull() : helperNote
            ])
            await onApproved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            isSaving = false
        }
    }

    private var reasonIcon: String {
        switch request.reason {
        case "Watch the kids": "figure.and.child.holdinghands"
        case "Watch the dog": "dog.fill"
        case "Cat care": "cat.fill"
        case "House sitting": "house.fill"
        case "Plant care": "leaf.fill"
        case "Pet sitting": "pawprint.fill"
        case "Eldercare": "heart.fill"
        default: "hand.raised.fill"
        }
    }

    private func friendlyDate(_ dateStr: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }
}

#Preview("Incoming Coverage") {
    NavigationStack { IncomingCoverageView() }
        .environment(APIService())
        .environment(AuthService())
}
