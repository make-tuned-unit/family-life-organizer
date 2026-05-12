import SwiftUI

struct EventDetailView: View {
    let appointment: AppointmentResponse
    var onUpdate: (() async -> Void)?

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingShareSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        categoryBadge
                        Spacer()
                        if let time = appointment.appointment_time, !time.isEmpty {
                            Text(time)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink2)
                        }
                    }

                    Text(appointment.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                        .tracking(-0.56)

                    // Date
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(TabAccent.calendar.color)
                        Text(formattedDate)
                            .font(.system(size: 15))
                            .foregroundStyle(WarmPalette.ink2)
                    }

                    // Location
                    if let location = appointment.location, !location.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(WarmPalette.bad)
                            Text(location)
                                .font(.system(size: 15))
                                .foregroundStyle(WarmPalette.ink2)
                        }

                        Button {
                            let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
                            if let url = URL(string: "maps://?q=\(query)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 14))
                                Text("Get Directions")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(WarmPalette.cream1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(WarmPalette.ink1)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    // Description
                    if let desc = appointment.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOTES")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink3)
                                .tracking(0.4)
                            Text(desc)
                                .font(.system(size: 15))
                                .foregroundStyle(WarmPalette.ink2)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(22)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 14)
                .padding(.bottom, 14)

                // People
                if let tags = appointment.person_tags, !tags.isEmpty {
                    WarmSectionHeader(title: "People")
                        .padding(.bottom, 8)

                    let names = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    VStack(spacing: 0) {
                        ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                            if index > 0 { GlassDivider() }
                            HStack(spacing: 12) {
                                FamilyAvatar(initial: String(name.prefix(1)).uppercased(), size: 32)
                                Text(name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(WarmPalette.ink1)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                    }
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.bottom, 14)
                }

                // Actions
                VStack(spacing: 10) {
                    // Share / Invite
                    ShareLink(item: shareText) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                            Text("Share Event")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(TabAccent.calendar.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Edit
                    Button {
                        showingEdit = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16))
                            Text("Edit Event")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(WarmPalette.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Delete
                    Button(role: .destructive) {
                        Task {
                            try? await api.deleteAppointment(id: appointment.id)
                            await onUpdate?()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                            Text("Delete Event")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(WarmPalette.bad)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
        }
        .background { AmbientBackground(style: .calendar) }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            EditAppointmentView(appointment: appointment) {
                Task { await onUpdate?() }
            }
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        guard let date = DateFormatter.isoDate.date(from: appointment.appointment_date) else {
            return appointment.appointment_date
        }
        return DateFormatter.longDate.string(from: date)
    }

    private var shareText: String {
        var parts = [appointment.title]
        parts.append(formattedDate)
        if let time = appointment.appointment_time, !time.isEmpty {
            parts.append("at \(time)")
        }
        if let location = appointment.location, !location.isEmpty {
            parts.append(location)
        }
        if let tags = appointment.person_tags, !tags.isEmpty {
            parts.append("with \(tags)")
        }
        return parts.joined(separator: "\n")
    }

    private var categoryColor: Color {
        switch appointment.category {
        case "medical": WarmPalette.bad
        case "school": AccentTheme.ocean.color
        case "daycare": AccentTheme.saffron.color
        case "work": AccentTheme.mauve.color
        default: TabAccent.calendar.color
        }
    }

    @ViewBuilder
    private var categoryBadge: some View {
        let label = appointment.category?.capitalized ?? "Event"
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(WarmPalette.cardSurface, in: Capsule())
    }
}

#Preview {
    NavigationStack {
        EventDetailView(appointment: AppointmentResponse(
            id: 1,
            title: "Pizza in the park",
            description: "Bring the kids",
            appointment_date: "2026-05-08",
            appointment_time: "17:00",
            location: "Victoria Park, Halifax",
            with_person: nil,
            category: "social",
            person_tags: "Jesse,Sophie",
            reminder_sent: nil,
            created_at: nil
        ))
    }
    .environment(APIService())
}
