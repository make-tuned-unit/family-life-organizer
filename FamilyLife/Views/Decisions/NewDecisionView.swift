import SwiftUI
import PhotosUI

struct NewDecisionView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var decisionType: DecisionType = .text
    @State private var bodyText = ""
    @State private var linkURL = ""
    @State private var pollOptions = ["", ""]
    @State private var isSaving = false
    @State private var error: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var expiryChoice: ExpiryChoice = .day
    @State private var shareGroupId: Int?

    enum ExpiryChoice: String, CaseIterable, Identifiable {
        case tonight = "Tonight"
        case day = "24 hours"
        case threeDays = "3 days"
        case week = "1 week"
        case never = "No expiry"

        var id: String { rawValue }

        var date: Date? {
            switch self {
            case .tonight:
                return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())
            case .day:
                return Date().addingTimeInterval(24 * 3600)
            case .threeDays:
                return Date().addingTimeInterval(3 * 24 * 3600)
            case .week:
                return Date().addingTimeInterval(7 * 24 * 3600)
            case .never:
                return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to ask?", text: $title)
                }

                Section("Type") {
                    Picker("Type", selection: $decisionType) {
                        ForEach(DecisionType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch decisionType {
                case .text:
                    Section("Details") {
                        TextField("Share your thoughts...", text: $bodyText, axis: .vertical)
                            .lineLimit(4)
                    }
                case .link:
                    Section("Link") {
                        TextField("Paste URL", text: $linkURL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Add context (optional)", text: $bodyText, axis: .vertical)
                            .lineLimit(2)
                    }
                case .photo:
                    Section("Photo") {
                        if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .frame(maxWidth: .infinity)
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(selectedImageData == nil ? "Choose Photo" : "Change Photo", systemImage: selectedImageData == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(TabAccent.decisions.color)
                        }
                        .onChange(of: selectedPhoto) {
                            Task {
                                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                }
                            }
                        }
                    }
                    Section("Details") {
                        TextField("What should the family look at?", text: $bodyText, axis: .vertical)
                            .lineLimit(3)
                    }
                case .poll:
                    Section("Options") {
                        ForEach(pollOptions.indices, id: \.self) { idx in
                            TextField("Option \(idx + 1)", text: $pollOptions[idx])
                        }
                        if pollOptions.count < 4 {
                            Button {
                                pollOptions.append("")
                            } label: {
                                Label("Add Option", systemImage: "plus.circle.fill")
                                    .foregroundStyle(TabAccent.decisions.color)
                            }
                        }
                    }
                    Section("Context") {
                        TextField("Add context (optional)", text: $bodyText, axis: .vertical)
                            .lineLimit(2)
                    }
                }

                Section("Expires") {
                    Picker(selection: $expiryChoice) {
                        ForEach(ExpiryChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    } label: {
                        Label("Time limit", systemImage: "clock")
                    }
                    .pickerStyle(.menu)
                }

                ShareWithSection(selectedGroupId: $shareGroupId)
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .decisions) }
            .navigationTitle("Share with Family")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t share decision", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        let filteredOptions = decisionType == .poll ? pollOptions.filter { !$0.isEmpty } : []
        if decisionType == .poll && filteredOptions.count < 2 {
            error = "Add at least two poll options."
            isSaving = false
            return
        }

        let expiresAt = expiryChoice.date
        var photoBase64: Any = NSNull()
        if decisionType == .photo, let imageData = selectedImageData {
            // Compress to JPEG for smaller payload
            if let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.7) {
                photoBase64 = compressed.base64EncodedString()
            }
        }

        let body: [String: Any] = [
            "title": title,
            "decision_type": decisionType.rawValue,
            "body": bodyText.isEmpty ? NSNull() : bodyText,
            "link_url": linkURL.isEmpty ? NSNull() : linkURL,
            "photo_data": photoBase64,
            "poll_options": filteredOptions,
            "creator_name": auth.currentUser?.name ?? "Me",
            "status": DecisionStatus.active.rawValue,
            "expires_at": expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        ]

        do {
            try await api.addDecision(body)
            if let groupId = shareGroupId {
                _ = try? await api.addFeedPost(groupId: groupId, data: [
                    "post_type": "decision",
                    "title": title,
                    "body": "\(auth.currentUser?.name ?? "Someone") wants input: \(title)"
                ])
            }
            await onSaved()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
            isSaving = false
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }
}

#Preview {
    NewDecisionView(onSaved: {})
        .environment(APIService())
}
