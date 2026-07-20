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
        case .custom: "e.g. Morning routine"
        }
    }

    private func defaultName(for t: RoutineType) -> String {
        switch t {
        case .period: "My cycle"
        case .babySleep: "Baby's sleep"
        case .sleepTraining: "Sleep training"
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
