import SwiftUI

/// Create a routine: pick a type, name it, and — for baby sleep / sleep training
/// — set the child's birthdate so the guided program can find the right phase.
struct NewRoutineView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void
    /// Prefill from a People card ("Start chores for Jude") — the type, the
    /// child's name, and their birthday when it's already on file.
    var initialType: RoutineType? = nil
    var initialSubject: String? = nil
    var initialBirthdate: String? = nil

    @State private var type: RoutineType = .sleepTraining
    @State private var name = ""
    @State private var subjectName = ""
    @State private var birthdate = Date()
    /// Only POST subject_birthdate when we have a real DOB — never silently
    /// stamp "today", which permanently shadows a later People-card birthday.
    @State private var birthdateConfirmed = false
    // Chores: the first chore, when in the day it happens, and the money side.
    @State private var firstChore = ""
    @State private var firstChoreSlots: Set<String> = ["morning", "evening"]
    @State private var allowanceText = ""
    @State private var bonusTitle = ""
    @State private var bonusAmountText = ""
    @State private var cycleMode = "period"          // period | ttc
    @State private var activityKind = ""             // e.g. "Violin"
    @State private var calendarKeyword = ""          // matches calendar event titles
    @State private var goalPerWeek = 1
    @State private var shareWithHousehold = false    // private until you say otherwise
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let accent = TabAccent.routines.color

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    typePicker

                    field(label: "Name") {
                        TextField(namePlaceholder, text: $name)
                            .font(.flBody)
                            .textInputAutocapitalization(.words)
                    }

                    field(label: type.needsBirthdate ? "Child's name" : "Who's it for (optional)") {
                        TextField(type == .period ? "e.g. Me" : "e.g. Wren", text: $subjectName)
                            .font(.flBody)
                            .textInputAutocapitalization(.words)
                    }

                    if type.needsBirthdate {
                        Toggle("Set date of birth on this routine", isOn: $birthdateConfirmed)
                            .font(.flBody)
                            .tint(accent)
                        if birthdateConfirmed {
                            field(label: "Date of birth") {
                                DatePicker("", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                                    .labelsHidden()
                                    .tint(accent)
                            }
                            Text("We use this to find the right phase and age-appropriate guidance. Prefer the People card when you can — that one repairs age everywhere.")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        } else {
                            Text("We’ll use their People-card birthday when the name matches. Turn this on only to set a date here.")
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }

                    if type.isCycle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What are you tracking?")
                                .font(.flCaption.weight(.semibold))
                                .foregroundStyle(WarmPalette.ink3)
                            Picker("Mode", selection: $cycleMode) {
                                Text("My period").tag("period")
                                Text("Trying to conceive").tag("ttc")
                            }
                            .pickerStyle(.segmented)
                            .tint(accent)
                        }
                        Text(cycleMode == "ttc"
                             ? "We'll estimate your fertile window from your cycle history. It's informational only — not medical advice, and not a form of birth control."
                             : "Log the first day of your period and we'll help you see your patterns and plan ahead.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }

                    if type.isChores {
                        choreFields
                    }

                    if type.isActivity {
                        field(label: "Activity") {
                            TextField("e.g. Violin, Swimming, Baseball", text: $activityKind)
                                .font(.flBody)
                                .textInputAutocapitalization(.words)
                        }
                        field(label: "Match calendar events containing") {
                            TextField(activityKind.isEmpty ? "e.g. violin" : activityKind.lowercased(), text: $calendarKeyword)
                                .font(.flBody)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Text("We'll find events with this word in their title so you can confirm each one and watch your milestones add up.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                        field(label: "Goal per week") {
                            Stepper("\(goalPerWeek) time\(goalPerWeek == 1 ? "" : "s") a week", value: $goalPerWeek, in: 1...14)
                                .font(.flBody)
                        }
                    }

                    shareToggle
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.top, 8)
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .inlineError(errorMessage) { errorMessage = nil }
            .onAppear {
                if let initialType { type = initialType; if name.isEmpty { name = defaultName(for: initialType) } }
                if let initialSubject, subjectName.isEmpty {
                    subjectName = initialSubject
                    if type.isChores { name = "\(initialSubject.split(separator: " ").first.map(String.init) ?? initialSubject)'s chores" }
                }
                if let initialBirthdate, let d = DateFormatter.isoDate.date(from: initialBirthdate) {
                    birthdate = d
                    birthdateConfirmed = true
                }
            }
        }
    }

    /// The chores starter: one chore, an optional allowance, an optional
    /// behaviour bonus. More can be added later from Manage — the research
    /// says start with one anyway.
    private var choreFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            field(label: "First chore") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("e.g. Feed the dog", text: $firstChore)
                        .font(.flBody)
                        .textInputAutocapitalization(.sentences)
                    HStack(spacing: 6) {
                        ForEach(["morning", "afternoon", "evening", "anytime"], id: \.self) { slot in
                            let on = firstChoreSlots.contains(slot)
                            Button {
                                if slot == "anytime" { firstChoreSlots = ["anytime"] }
                                else {
                                    firstChoreSlots.remove("anytime")
                                    if on { firstChoreSlots.remove(slot) } else { firstChoreSlots.insert(slot) }
                                    if firstChoreSlots.isEmpty { firstChoreSlots = ["anytime"] }
                                }
                            } label: {
                                Text(slot.capitalized)
                                    .font(.flCaption.weight(.medium))
                                    .foregroundStyle(on ? .white : accent)
                                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                                    .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                                    .background(on ? accent : accent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("One chore, tied to a moment in the day, is the right start at any age. You can add more once it sticks.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)

            field(label: "Weekly allowance (optional)") {
                HStack {
                    Text(Locale.current.currencySymbol ?? "$").font(.flBody).foregroundStyle(WarmPalette.ink3)
                    TextField("2.00", text: $allowanceText).font(.flBody).keyboardType(.decimalPad)
                }
            }
            field(label: "Behaviour bonus (optional)") {
                HStack(spacing: 10) {
                    TextField("e.g. Good bedtime", text: $bonusTitle).font(.flBody)
                    Text("+").foregroundStyle(WarmPalette.ink3)
                    TextField("1.00", text: $bonusAmountText).font(.flBody).keyboardType(.decimalPad).frame(width: 64)
                }
            }
            Text("Allowance stays fixed — it's never docked for a missed chore. A bonus pays once a week for something you're working on.")
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
        }
    }

    /// Off by default — a routine belongs to whoever made it until they say
    /// otherwise. Sharing makes it visible AND loggable to the whole household.
    private var shareToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $shareWithHousehold) {
                HStack(spacing: 10) {
                    Image(systemName: shareWithHousehold ? "person.2.fill" : "lock.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(shareWithHousehold ? accent : WarmPalette.ink3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shareWithHousehold ? "Shared with your household" : "Just for you")
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text(shareWithHousehold
                             ? "Everyone at home can see this and log to it."
                             : "Only you can see this. You can share it any time.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }
            .tint(accent)
            .padding(12)
            .flCard(tint: shareWithHousehold ? accent.opacity(0.06) : .clear)
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What are you tracking?")
                .font(.flCaption.weight(.semibold))
                .foregroundStyle(WarmPalette.ink3)
            ForEach(RoutineType.allCases) { t in
                Button {
                    type = t
                    if name.isEmpty { name = defaultName(for: t) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(type == t ? .white : accent)
                            .frame(width: 34, height: 34)
                            .background(type == t ? accent : accent.opacity(0.15))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayName)
                                .font(.flSubheadline.weight(.semibold))
                                .foregroundStyle(WarmPalette.ink1)
                            Text(t.blurb)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if type == t {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(12)
                    .flCard(tint: type == t ? accent.opacity(0.06) : .clear)
                }
                .buttonStyle(.flCardPress)
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.flCaption.weight(.semibold))
                .foregroundStyle(WarmPalette.ink3)
            content()
                .padding(12)
                .flCard()
        }
    }

    private var namePlaceholder: String {
        switch type {
        case .period: "e.g. My cycle"
        case .babySleep: "e.g. Wren's sleep"
        case .sleepTraining: "e.g. Wren's sleep training"
        case .activity: "e.g. Mia's violin"
        case .chores: "e.g. Jude's chores"
        case .custom: "e.g. Morning routine"
        }
    }

    private func defaultName(for t: RoutineType) -> String {
        switch t {
        case .period: "My cycle"
        case .babySleep: "Baby's sleep"
        case .sleepTraining: "Sleep training"
        case .activity: ""
        case .chores: "Chores"
        case .custom: ""
        }
    }

    private func save() async {
        isSaving = true
        var body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "routine_type": type.rawValue,
            "shared_scope": shareWithHousehold ? "household" : "private",
        ]
        let subject = subjectName.trimmingCharacters(in: .whitespaces)
        if !subject.isEmpty { body["subject_name"] = subject }
        if type.needsBirthdate && birthdateConfirmed {
            let fmt = DateFormatter()
            fmt.calendar = Calendar(identifier: .gregorian)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            body["subject_birthdate"] = fmt.string(from: birthdate)
        }
        if type.isCycle {
            body["config"] = ["mode": cycleMode]
        }
        if type.isChores {
            var cfg = ChoreConfig.empty
            cfg.allowance.currency = Locale.current.currency?.identifier ?? "USD"
            cfg.allowance.weekly_amount = Double(allowanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let chore = firstChore.trimmingCharacters(in: .whitespaces)
            if !chore.isEmpty {
                let slots = ["morning", "afternoon", "evening", "anytime"].filter { firstChoreSlots.contains($0) }
                cfg.chores = [.init(id: ManageChoresSheet.slug(chore), title: chore, icon: ManageChoresSheet.icon(for: chore),
                                    slots: slots, days: nil, active: true, started_on: DateFormatter.isoDate.string(from: Date()))]
            }
            let bonus = bonusTitle.trimmingCharacters(in: .whitespaces)
            if !bonus.isEmpty, let amount = Double(bonusAmountText.replacingOccurrences(of: ",", with: ".")) {
                cfg.bonuses = [.init(id: ManageChoresSheet.slug(bonus), title: bonus, amount: amount, icon: "star.fill")]
            }
            body["config"] = cfg.jsonObject
            // A child's chore chart is a household thing by nature — both
            // parents tick it. Sleep and cycles stay private by default.
            if !shareWithHousehold { body["shared_scope"] = "household" }
        }
        if type.isActivity {
            let kind = activityKind.trimmingCharacters(in: .whitespaces)
            let keyword = calendarKeyword.trimmingCharacters(in: .whitespaces).lowercased()
            body["config"] = [
                "activity_kind": kind,
                "calendar_keyword": keyword.isEmpty ? kind.lowercased() : keyword,
                "goal_per_week": goalPerWeek,
            ]
        }
        do {
            try await api.addRoutine(body)
            onCreated()
            dismiss()
        } catch {
            errorMessage = "Couldn't create that routine. Please try again."
            isSaving = false
        }
    }
}

#Preview {
    NewRoutineView(onCreated: {})
        .environment(APIService())
}
