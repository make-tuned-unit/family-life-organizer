import SwiftUI
import PhotosUI
import AVFoundation

struct ReceiptScannerView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    /// If set, scanned receipt is saved as a project expense instead of a budget receipt
    var projectId: Int?
    var projectName: String?
    var onProjectExpenseSaved: (() async -> Void)?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var scanResult: ScanResult?
    @State private var isScanning = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingCamera = false
    @State private var cameraPermissionDenied = false
    @State private var showingScanAnother = false
    @State private var savedCount = 0

    private var isProjectMode: Bool { projectId != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if imageData == nil && !isScanning {
                        sourcePickerSection
                    }


                    if isScanning {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("Scanning receipt with AI...")
                                .font(.subheadline)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    if let error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AccentTheme.saffron.color)
                            Text(error).font(.subheadline)
                        }
                        .padding()
                        .background(TabAccent.expenses.color.opacity(DesignTokens.Opacity.cardTint))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    if cameraPermissionDenied {
                        VStack(spacing: 8) {
                            Text("Camera access denied")
                                .font(.subheadline.weight(.semibold))
                            Text("Go to Settings > Kinrows to enable camera access.")
                                .font(.caption)
                                .foregroundStyle(WarmPalette.ink3)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .padding()
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    if let result = scanResult {
                        scanResultSection(result)
                    }
                }
                .padding(.vertical)
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .expenses).ignoresSafeArea() }
            .navigationTitle(isProjectMode ? "Scan for \(projectName ?? "Project")" : "Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: selectedPhoto) { loadAndScan() }
            .sheet(isPresented: $showingCamera) {
                CameraView { data in
                    imageData = data
                    scanImage(data)
                }
                .ignoresSafeArea()
            }
            .alert("Receipt Saved", isPresented: $showingScanAnother) {
                Button("Scan Another") { resetForNextScan() }
                Button("Done") { dismiss() }
            } message: {
                Text("\(savedCount) receipt\(savedCount == 1 ? "" : "s") saved. Scan another?")
            }
        }
    }

    // MARK: - Source Picker

    private var sourcePickerSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(TabAccent.expenses.color)
                .padding(.bottom, 4)

            Text(isProjectMode ? "Scan receipt for \(projectName ?? "project")" : "Scan a receipt")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
            Text("Take a photo or choose from your library. AI will extract the merchant, items, and total.")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Camera button
            Button { requestCameraAndShow() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                    Text("Take Photo")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(WarmPalette.cream1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WarmPalette.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 22)

            // Photo library
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                    Text("Choose from Library")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(WarmPalette.ink1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 20)
    }

    // MARK: - Scan Results

    private func scanResultSection(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(result.merchant).font(.headline)
                    Text(result.date).font(.caption).foregroundStyle(WarmPalette.ink3)
                }
                Spacer()
                Text("$\(result.total, specifier: "%.2f")")
                    .font(.title2.bold())
                    .foregroundStyle(TabAccent.home.color)
            }
            .padding()
            .background(WarmPalette.ink1.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isProjectMode {
                HStack(spacing: 8) {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(AccentTheme.sage.color)
                    Text("Saving to: \(projectName ?? "Project")")
                        .font(.subheadline.weight(.medium))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AccentTheme.sage.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Items Found").font(.headline)
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WarmPalette.good)
                    Text(item.name).font(.subheadline)
                    Spacer()
                    if let price = item.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.subheadline).foregroundStyle(WarmPalette.ink3)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
            }

            HStack {
                Text(isProjectMode ? "Project" : "Category").font(.subheadline.weight(.medium))
                Spacer()
                Text(isProjectMode ? (projectName ?? "Project") : result.category)
                    .font(.subheadline)
                    .padding(.horizontal, DesignTokens.Spacing.inset)
                    .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                    .background((isProjectMode ? AccentTheme.sage.color : AccentTheme.ocean.color).opacity(DesignTokens.Opacity.cardTint))
                    .clipShape(Capsule())
            }

            Button { save() } label: {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(isProjectMode ? "Add to Project" : "Save Receipt")
                        .font(.headline).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isProjectMode ? AccentTheme.sage.color : TabAccent.home.color)
            .controlSize(.large)
            .disabled(isSaving)

            Button {
                imageData = nil
                scanResult = nil
                selectedPhoto = nil
                error = nil
            } label: {
                Text("Scan another")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WarmPalette.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func requestCameraAndShow() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = "Camera not available on this device."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showingCamera = true }
                    else { cameraPermissionDenied = true }
                }
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
        @unknown default:
            showingCamera = true
        }
    }

    private func resetForNextScan() {
        scanResult = nil
        imageData = nil
        selectedPhoto = nil
        error = nil
    }

    private func loadAndScan() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            imageData = data
            scanImage(data)
        }
    }

    private func scanImage(_ data: Data) {
        isScanning = true
        error = nil
        Task {
            do {
                scanResult = try await api.scanReceipt(imageData: data)
            } catch {
                self.error = "Could not scan receipt. Try adding manually."
            }
            isScanning = false
        }
    }

    private func save() {
        guard let result = scanResult else { return }
        isSaving = true
        Task {
            do {
                if let projectId {
                    // Save as project expense — tag with project name, items in notes
                    let itemDetail = result.items.map { item in
                        if let price = item.price {
                            return "\(item.name) — $\(String(format: "%.2f", price))"
                        }
                        return item.name
                    }.joined(separator: "\n")
                    let expenseData: [String: Any] = [
                        "description": result.merchant,
                        "amount": result.total,
                        "category": projectName ?? "General",
                        "notes": "\(result.category) receipt\n\(itemDetail)"
                    ]
                    let _ = try await api.addProjectExpense(projectId: projectId, expense: expenseData)
                    // Dismiss first, then let parent reload — avoids task cancellation race
                    dismiss()
                    // Fire-and-forget: parent will pick up changes
                    Task.detached { await onProjectExpenseSaved?() }
                    return
                } else {
                    // Save as budget receipt with item breakdown in notes
                    let itemDetail = result.items.map { item in
                        if let price = item.price {
                            return "\(item.name) — $\(String(format: "%.2f", price))"
                        }
                        return item.name
                    }.joined(separator: "\n")
                    try await api.saveScannedReceipt(result: result, notes: itemDetail)
                    savedCount += 1
                    isSaving = false
                    showingScanAnother = true
                    return
                }
            } catch {
                self.error = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        init(onCapture: @escaping (Data) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onCapture(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - API Response Types

struct ScanResult: Codable {
    let merchant: String
    let date: String
    let total: Double
    let category: String
    let items: [ScanItem]
}

struct ScanItem: Codable {
    let name: String
    let price: Double?
    let quantity: String?
}

#Preview {
    ReceiptScannerView()
        .environment(APIService())
}
