import SwiftUI

// MARK: - Incoming Coverage Components (helper's view)
// The standalone IncomingCoverageView screen was superseded by the combined
// MyCoverageRequestsView; this file keeps its live pieces — the request card
// and the approve sheet.

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
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(request.reason)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink2)
                }
                Spacer()

                if request.recipient_status == "approved" {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Approved")
                            .font(.flCaption.weight(.semibold))
                    }
                    .foregroundStyle(WarmPalette.good)
                } else {
                    Button(action: onApprove) {
                        Text("Review")
                            .font(.flFootnote.weight(.semibold))
                            .foregroundStyle(TabAccent.care.color)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(TabAccent.care.color.opacity(0.12), in: Capsule())
                    }
                }
            }

            if let note = request.note, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(.flFootnote).italic()
                    .foregroundStyle(WarmPalette.ink3)
            }

            if let date = request.created_at {
                Text(relativeTime(date))
                    .font(.flCaption)
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
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("COVERAGE REQUEST")
                        .font(.flOverline)
                        .foregroundStyle(TabAccent.care.color).tracking(0.4)
                    Text("\(request.requester_name) needs help")
                        .font(.flTitle)
                        .foregroundStyle(WarmPalette.ink1)
                    Label(request.reason, systemImage: reasonIcon)
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.top, 10).padding(.bottom, 18)

                if let note = request.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.flSubheadline).italic()
                        .foregroundStyle(WarmPalette.ink2)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .flCard()
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)
                }

                // Window selection
                Text("PICK A TIME SLOT")
                    .font(.flOverline)
                    .foregroundStyle(WarmPalette.ink3).tracking(0.4)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 8)

                if isLoading {
                    FLLoadingState(message: "Loading time slots…")
                } else {
                    VStack(spacing: 8) {
                        ForEach(windows) { window in
                            let isSelected = selectedWindow?.id == window.id
                            Button { selectedWindow = window } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friendlyDate(window.window_date))
                                            .font(.flSubheadline.weight(.semibold))
                                            .foregroundStyle(WarmPalette.ink1)
                                        Text("\(window.start_time) – \(window.end_time)")
                                            .font(.flSubheadline.weight(.medium))
                                            .foregroundStyle(TabAccent.care.color)
                                        if let desc = window.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.flFootnote)
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
                                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                        .stroke(isSelected ? TabAccent.care.color.opacity(0.4) : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 14)
                }

                // Note
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD A NOTE (OPTIONAL)")
                        .font(.flOverline)
                        .foregroundStyle(WarmPalette.ink3).tracking(0.4)
                    TextField("e.g. We'll bring lunch!", text: $helperNote)
                        .font(.system(size: 15)).foregroundStyle(WarmPalette.ink2)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin).padding(.bottom, 18)

                // Approve button
                Button {
                    Task { await approve() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                        }
                        Text("Confirm availability")
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.flCTA)
                .disabled(selectedWindow == nil || isSaving)
                .opacity(selectedWindow == nil ? 0.5 : 1)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
        .background { AmbientBackground(style: .care) }
        .inlineError(errorMessage) { errorMessage = nil }
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
            errorMessage = "Couldn't confirm — \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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

#Preview("Approve Request") {
    NavigationStack {
        ApproveRequestSheet(
            request: APIService.IncomingCoverageRequest(
                id: 1, reason: "Watch the kids", note: "Back by 9pm!", status: "pending",
                created_at: nil, requester_name: "Melissa", recipient_id: 1,
                recipient_status: "pending", invite_token: nil
            )
        ) {}
    }
    .environment(APIService())
    .environment(AuthService())
}
