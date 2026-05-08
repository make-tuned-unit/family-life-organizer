import SwiftUI

// MARK: - Coverage Cascade
// General-purpose coverage request flow:
// 1. Ask someone to cover a time slot (childcare, dog sitting, house sitting, etc.)
// 2. Wait for their confirmation
// 3. Once confirmed, that block unlocks in your calendar
// 4. Book whatever you needed to do into the unlocked window

struct CoverageCascadeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var currentStep: CoverageStep = .ask

    // Shared state across steps
    @State private var selectedPeople: [String] = []
    @State private var coverageReason: CoverageReason = .kids
    @State private var candidateWindows: [CandidateWindow] = []
    @State private var noteText: String = ""
    @State private var newPersonName: String = ""
    @State private var showingAddPerson = false
    @State private var customReason: String = ""

    enum CoverageStep: Int, CaseIterable {
        case ask = 1, pending, confirmed, booking
    }

    var body: some View {
        Group {
            switch currentStep {
            case .ask:
                CoverageAskView(
                    selectedPeople: $selectedPeople,
                    coverageReason: $coverageReason,
                    candidateWindows: $candidateWindows,
                    noteText: $noteText,
                    customReason: $customReason,
                    showingAddPerson: $showingAddPerson,
                    newPersonName: $newPersonName,
                    onSend: { currentStep = .pending }
                )
            case .pending:
                CoveragePendingView(
                    selectedPeople: selectedPeople,
                    coverageReason: coverageReason,
                    onConfirmed: { currentStep = .confirmed }
                )
            case .confirmed:
                CoverageConfirmedView(
                    selectedPeople: selectedPeople,
                    onBook: { currentStep = .booking }
                )
            case .booking:
                CoverageBookingView(
                    selectedPeople: selectedPeople,
                    onComplete: { dismiss() }
                )
            }
        }
        .background { AmbientBackground(style: .care) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentStep != .ask {
                    Button {
                        if let prev = CoverageStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                } else {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Step \(currentStep.rawValue) of 4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
        }
        .task { await loadCandidateWindows() }
    }

    private func loadCandidateWindows() async {
        let cal = Calendar.current
        let today = Date()
        guard let weekEnd = cal.date(byAdding: .day, value: 14, to: today) else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        do {
            let appointments = try await api.fetchAppointments(
                dateFrom: fmt.string(from: today),
                dateTo: fmt.string(from: weekEnd)
            )

            // Build candidate windows from days that have appointments (= busy times needing coverage)
            var windowsByDate: [String: [AppointmentResponse]] = [:]
            for appt in appointments {
                windowsByDate[appt.appointment_date, default: []].append(appt)
            }

            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "yyyy-MM-dd"
            let displayDayFmt = DateFormatter()
            displayDayFmt.dateFormat = "EEEE"
            let displayDateFmt = DateFormatter()
            displayDateFmt.dateFormat = "MMM d"

            var windows: [CandidateWindow] = []
            for (dateStr, appts) in windowsByDate.sorted(by: { $0.key < $1.key }) {
                guard let date = dayFmt.date(from: dateStr) else { continue }
                let dayName = displayDayFmt.string(from: date)
                let dateName = displayDateFmt.string(from: date)
                let reasons = appts.compactMap { appt -> String? in
                    let tags = appt.person_tags ?? ""
                    let who = tags.isEmpty ? "" : "\(tags): "
                    return "\(who)\(appt.title)"
                }.joined(separator: " / ")

                // Suggest a coverage window (9 AM to 3 PM as default)
                let startTime = appts.compactMap { $0.appointment_time }.sorted().first ?? "9:00 AM"
                windows.append(CandidateWindow(
                    day: dayName,
                    date: dateName,
                    window: "\(startTime) - 3:00 PM",
                    hours: "5h",
                    reason: reasons
                ))
            }

            candidateWindows = windows
        } catch {
            // If we can't load appointments, start with empty windows
        }
    }
}

// Keep old name as typealias so CalendarView reference compiles
typealias CareCascadeView = CoverageCascadeView

// MARK: - Data Types

enum CoverageReason: String, CaseIterable {
    case kids = "Watch the kids"
    case dog = "Watch the dog"
    case house = "House sitting"
    case custom = "Custom..."

    var icon: String {
        switch self {
        case .kids: "figure.and.child.holdinghands"
        case .dog: "dog.fill"
        case .house: "house.fill"
        case .custom: "pencil"
        }
    }
}

struct CandidateWindow: Identifiable {
    let id = UUID()
    var day: String
    var date: String
    var window: String
    var hours: String
    var reason: String
}

// MARK: - Step 1: Ask for Coverage

struct CoverageAskView: View {
    @Binding var selectedPeople: [String]
    @Binding var coverageReason: CoverageReason
    @Binding var candidateWindows: [CandidateWindow]
    @Binding var noteText: String
    @Binding var customReason: String
    @Binding var showingAddPerson: Bool
    @Binding var newPersonName: String
    let onSend: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW COVERAGE REQUEST")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color)
                        .tracking(0.4)
                    Text("Ask someone to\ncover a time slot.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("Send your candidate windows. Once they confirm, those blocks unlock in your calendar so you can book what you need to do.")
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink2)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 18)

                // Who to ask
                sectionLabel("Ask")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedPeople, id: \.self) { person in
                            personChip(initial: String(person.prefix(1)).uppercased(), name: person)
                                .onTapGesture {
                                    selectedPeople.removeAll { $0 == person }
                                }
                        }
                        addChip
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 14)

                // What needs coverage
                sectionLabel("What needs coverage")
                VStack(spacing: 8) {
                    ForEach(CoverageReason.allCases, id: \.self) { reason in
                        coverageReasonChip(
                            icon: reason.icon,
                            label: reason == .custom && !customReason.isEmpty ? customReason : reason.rawValue,
                            selected: coverageReason == reason
                        )
                        .onTapGesture {
                            coverageReason = reason
                        }
                    }
                    if coverageReason == .custom {
                        TextField("What do you need?", text: $customReason)
                            .font(.system(size: 15))
                            .padding(12)
                            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)

                // Candidate windows
                sectionLabel("Candidate windows")
                VStack(spacing: 10) {
                    if candidateWindows.isEmpty {
                        Text("No upcoming busy days found. Add a window manually.")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(candidateWindows) { window in
                            CandidateWindowRow(day: window.day, date: window.date, window: window.window, hours: window.hours, reason: window.reason)
                        }
                    }

                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16))
                            Text("Add another window")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(WarmPalette.ink3)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundStyle(WarmPalette.ink1.opacity(0.08))
                    )
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 14)

                // Note
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPTIONAL NOTE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                        .tracking(0.4)
                    TextField("Add a note for them...", text: $noteText)
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 14)

                // Send
                Button(action: onSend) {
                    HStack(spacing: 8) {
                        Text("Send request")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(WarmPalette.cream1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WarmPalette.ink1)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .disabled(selectedPeople.isEmpty)
                .opacity(selectedPeople.isEmpty ? 0.5 : 1)
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)

                Text("They'll get a notification with one-tap reply.")
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
            }
        }
        .alert("Add person", isPresented: $showingAddPerson) {
            TextField("Name", text: $newPersonName)
            Button("Add") {
                if !newPersonName.isEmpty {
                    selectedPeople.append(newPersonName)
                    newPersonName = ""
                }
            }
            Button("Cancel", role: .cancel) { newPersonName = "" }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WarmPalette.ink3)
            .tracking(0.4)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
    }

    private func personChip(initial: String, name: String) -> some View {
        HStack(spacing: 8) {
            FamilyAvatar(initial: initial, size: 28)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
    }

    private var addChip: some View {
        Button { showingAddPerson = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                Text("add")
                    .font(.system(size: 13))
            }
            .foregroundStyle(WarmPalette.ink3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(WarmPalette.ink1.opacity(0.08))
            )
        }
    }

    private func coverageReasonChip(icon: String, label: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(selected ? TabAccent.care.color : WarmPalette.ink3)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? WarmPalette.ink1 : WarmPalette.ink2)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(TabAccent.care.color)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(selected ? TabAccent.care.color.opacity(0.06) : .white.opacity(0.03)), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? TabAccent.care.color.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

// MARK: - Candidate Window Row

struct CandidateWindowRow: View {
    let day: String
    let date: String
    let window: String
    let hours: String
    let reason: String
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text(day)
                        .font(.system(size: 15, weight: .bold))
                    Text(date)
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                Text(hours)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
            }
            Text(window)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TabAccent.care.color)
            Text(reason)
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(highlighted ? TabAccent.care.color.opacity(0.06) : .white.opacity(0.03)), in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(highlighted ? TabAccent.care.color : .clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Step 2: Pending

struct CoveragePendingView: View {
    let selectedPeople: [String]
    let coverageReason: CoverageReason
    let onConfirmed: () -> Void

    private var peopleNames: String {
        selectedPeople.joined(separator: " & ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COVERAGE REQUEST SENT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink3)
                        .tracking(0.4)
                    Text("Waiting for reply")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 12)

                // Status banner
                HStack(spacing: 12) {
                    ZStack {
                        ForEach(Array(selectedPeople.prefix(2).enumerated()), id: \.offset) { index, person in
                            FamilyAvatar(initial: String(person.prefix(1)).uppercased(), size: 28)
                                .offset(x: CGFloat(index * 12 - 6), y: CGFloat(index * 12 - 6))
                        }
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(peopleNames)
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 6) {
                            Circle()
                                .fill(WarmPalette.warn)
                                .frame(width: 6, height: 6)
                            Text("Sent just now - waiting for reply")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }

                    Spacer()

                    Button("Nudge") {}
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.white.opacity(0.05).interactive()), in: .capsule)
                }
                .padding(14)
                .glassEffect(.regular.tint(WarmPalette.warn.opacity(0.04)), in: .rect(cornerRadius: 22))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(LinearGradient(colors: [WarmPalette.warn, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 14)

                // Simulate confirmation
                Button(action: onConfirmed) {
                    Text("Simulate: coverage confirmed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarmPalette.cream1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(TabAccent.care.color)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Step 3: Confirmed (Unlock)

struct CoverageConfirmedView: View {
    let selectedPeople: [String]
    let onBook: () -> Void

    private var peopleNames: String {
        selectedPeople.joined(separator: " & ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Confirmation hero
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            ForEach(Array(selectedPeople.prefix(2).enumerated()), id: \.offset) { index, person in
                                FamilyAvatar(initial: String(person.prefix(1)).uppercased(), size: 28)
                                    .offset(x: CGFloat(index * 12 - 6), y: CGFloat(index * 12 - 6))
                            }
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(peopleNames) confirmed")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Replied just now")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(WarmPalette.good)
                            .clipShape(Circle())
                    }

                    // Confirmed window
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONFIRMED WINDOW")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WarmPalette.good)
                            .tracking(0.4)
                        Text("Coverage approved")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text("You can now book into this window")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WarmPalette.good.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(WarmPalette.good.opacity(0.28), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(22)
                .glassEffect(.regular.tint(WarmPalette.good.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(LinearGradient(colors: [WarmPalette.good, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 14)
                .padding(.bottom, 18)

                // Book button
                Button(action: onBook) {
                    Text("Book into this window")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WarmPalette.cream1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WarmPalette.ink1)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Step 4: Book Into Window

struct CoverageBookingView: View {
    let selectedPeople: [String]
    let onComplete: () -> Void

    @State private var bookingTitle = ""
    @State private var bookingWho = "Jesse"
    @State private var bookingLocation = ""

    private var peopleNames: String {
        selectedPeople.joined(separator: " & ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Unlocked banner
                HStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(WarmPalette.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coverage confirmed")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.good)
                        Text("\(peopleNames) - window available")
                            .font(.system(size: 13))
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WarmPalette.good.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(WarmPalette.good.opacity(0.32), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 12)
                .padding(.bottom, 14)

                // Booking form
                VStack(alignment: .leading, spacing: 0) {
                    Text("BOOKING INTO UNLOCKED WINDOW")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TabAccent.care.color)
                        .tracking(0.4)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        BookingFormField(label: "What", placeholder: "e.g. Dental cleaning", text: $bookingTitle)
                        GlassDivider()
                        BookingFormField(label: "Who", placeholder: "Jesse", text: $bookingWho)
                        GlassDivider()
                        BookingFormField(label: "Location", placeholder: "Optional", text: $bookingLocation)
                    }

                    HStack(spacing: 8) {
                        Button(action: onComplete) {
                            Text("Add to calendar")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.cream1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(WarmPalette.ink1)
                                .clipShape(Capsule())
                        }
                        .disabled(bookingTitle.isEmpty)
                        .opacity(bookingTitle.isEmpty ? 0.5 : 1)

                        Button { } label: {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .glassEffect(.regular.tint(.white.opacity(0.05)), in: .capsule)
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(18)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 22))
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
    }
}

struct BookingFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
                .frame(width: 70, alignment: .leading)
            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WarmPalette.ink1)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview("Coverage Cascade") {
    NavigationStack {
        CoverageCascadeView()
    }
    .environment(APIService())
}
