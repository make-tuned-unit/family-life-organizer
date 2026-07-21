import SwiftUI

/// Create a routine: pick a type, name it, and — for baby sleep / sleep training
/// — set the child's birthdate so the guided program can find the right phase.
struct NewRoutineView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var type: RoutineType = .sleepTraining
    @State private var name = ""
    @State private var subjectName = ""
    @State private var birthdate = Date()
    @State private var cycleMode = "period"          // period | ttc
    @State private var activityKind = ""             // e.g. "Violin"
    @State private var calendarKeyword = ""          // matches calendar event titles
    @State private var goalPerWeek = 1
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
                        field(label: "Date of birth") {
                            DatePicker("", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .tint(accent)
                        }
                        Text("We use this to find the right phase and age-appropriate guidance — nothing is shared outside your household.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
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
        case .custom: "e.g. Morning routine"
        }
    }

    private func defaultName(for t: RoutineType) -> String {
        switch t {
        case .period: "My cycle"
        case .babySleep: "Baby's sleep"
        case .sleepTraining: "Sleep training"
        case .activity: ""
        case .custom: ""
        }
    }

    private func save() async {
        isSaving = true
        var body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "routine_type": type.rawValue,
        ]
        let subject = subjectName.trimmingCharacters(in: .whitespaces)
        if !subject.isEmpty { body["subject_name"] = subject }
        if type.needsBirthdate {
            let fmt = DateFormatter()
            fmt.calendar = Calendar(identifier: .gregorian)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            body["subject_birthdate"] = fmt.string(from: birthdate)
        }
        if type.isCycle {
            body["config"] = ["mode": cycleMode]
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
