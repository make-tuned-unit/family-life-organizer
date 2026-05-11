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

        let expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86_400)
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
            "expires_at": ISO8601DateFormatter().string(from: expiresAt)
        ]

        do {
            try await api.addDecision(body)
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
