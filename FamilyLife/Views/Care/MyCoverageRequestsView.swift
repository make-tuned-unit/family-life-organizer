import SwiftUI

// MARK: - My Coverage Requests (requester's view)
// Shows coverage requests the current user has sent, with status tracking.

struct MyCoverageRequestsView: View {
    @Environment(APIService.self) private var api
    @State private var requests: [APIService.CoverageRequestResponse] = []
    @State private var isLoading = false
    @State private var selectedDetail: APIService.CoverageDetailResponse?
    @State private var showingCareCascade = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MY REQUESTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color).tracking(0.4)
                    Text("Coverage requests")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18)

                if isLoading && requests.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 32))
                            .foregroundStyle(WarmPalette.ink4)
                        Text("No requests yet")
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink3)
                        Button { showingCareCascade = true } label: {
                            Text("Send a coverage request")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(TabAccent.care.color)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(TabAccent.care.color.opacity(0.12), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(requests) { request in
                            Button {
                                Task { await loadDetail(id: request.id) }
                            } label: {
                                MyCoverageRequestCard(request: request)
                            }
                            .buttonStyle(.plain)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus") {
                    showingCareCascade = true
                }
            }
        }
        .refreshable { await loadRequests() }
        .task { await loadRequests() }
        .sheet(item: $selectedDetail) { detail in
            NavigationStack { CoverageDetailSheet(detail: detail) }
        }
        .sheet(isPresented: $showingCareCascade) {
            NavigationStack {
                CareCascadeView()
            }
        }
    }

    private func loadRequests() async {
        isLoading = true
        requests = (try? await api.fetchCoverageRequests()) ?? []
        isLoading = false
    }

    private func loadDetail(id: Int) async {
        selectedDetail = try? await api.fetchCoverageDetail(id: id)
    }
}

// MARK: - Request Card

struct MyCoverageRequestCard: View {
    let request: APIService.CoverageRequestResponse

    private var statusColor: Color {
        switch request.status {
        case "approved": WarmPalette.good
        case "cancelled": WarmPalette.ink4
        default: WarmPalette.warn
        }
    }

    private var statusLabel: String {
        switch request.status {
        case "approved": "Approved"
        case "cancelled": "Cancelled"
        case "expired": "Expired"
        default: "Pending"
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reasonIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TabAccent.care.color)
                .frame(width: 36, height: 36)
                .background(TabAccent.care.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(request.reason)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    if let count = request.approval_count, count > 0 {
                        Text("\(count)/\(request.recipient_count ?? 0) approved")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    } else {
                        Text("\(request.recipient_count ?? 0) asked")
                            .font(.system(size: 12))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmPalette.ink4)
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

// MARK: - Coverage Detail Sheet

struct CoverageDetailSheet: View {
    let detail: APIService.CoverageDetailResponse
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(detail.status.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(statusColor).tracking(0.4)
                    }
                    Text(detail.reason)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    if let note = detail.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)

                // Windows
                sectionLabel("TIME WINDOWS")
                VStack(spacing: 6) {
                    ForEach(detail.windows) { window in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friendlyDate(window.window_date))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink1)
                                Text("\(window.start_time) – \(window.end_time)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(TabAccent.care.color)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 18)

                // Recipients
                sectionLabel("CARE TEAM")
                VStack(spacing: 6) {
                    ForEach(detail.recipients) { recipient in
                        HStack(spacing: 12) {
                            FamilyAvatar(initial: recipient.avatar_initial ?? String(recipient.contact_name.prefix(1)).uppercased(), size: 32)
                            Text(recipient.contact_name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Spacer()
                            recipientStatusBadge(recipient.status)
                        }
                        .padding(12)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 18)

                // Approvals
                if !detail.approvals.isEmpty {
                    sectionLabel("CONFIRMED")
                    VStack(spacing: 6) {
                        ForEach(detail.approvals) { approval in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(approval.helper_name ?? "Helper")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(WarmPalette.ink1)
                                    Spacer()
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(WarmPalette.good)
                                }
                                Text("\(approval.approved_date) · \(approval.approved_start) – \(approval.approved_end)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AccentTheme.sage.color)
                                if let note = approval.helper_note, !note.isEmpty {
                                    Text("\"\(note)\"")
                                        .font(.system(size: 13)).italic()
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                            }
                            .padding(12)
                            .background(AccentTheme.sage.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 18)
                }
            }
            .padding(.bottom, 40)
        }
        .background { AmbientBackground(style: .care) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.foregroundStyle(WarmPalette.ink2)
            }
        }
    }

    private var statusColor: Color {
        switch detail.status {
        case "approved": WarmPalette.good
        case "cancelled": WarmPalette.ink4
        default: WarmPalette.warn
        }
    }

    private func recipientStatusBadge(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(status == "approved" ? WarmPalette.good : WarmPalette.warn).frame(width: 6, height: 6)
            Text(status.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status == "approved" ? WarmPalette.good : WarmPalette.ink3)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WarmPalette.ink3).tracking(0.4)
            .padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func friendlyDate(_ dateStr: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }
}

// Make CoverageDetailResponse Identifiable for sheet presentation
extension APIService.CoverageDetailResponse: @retroactive Identifiable { }

#Preview("My Coverage Requests") {
    NavigationStack { MyCoverageRequestsView() }
        .environment(APIService())
}
