import SwiftUI
import PhotosUI

struct ReceiptScannerView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var scanResult: ScanResult?
    @State private var isScanning = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var addToPantry = true
    @State private var showingCamera = false
    @State private var showingSourcePicker = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if showingSourcePicker && imageData == nil && !isScanning {
                        sourcePickerSection
                    } else if imageData == nil && !isScanning {
                        photoPickerSection
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

                    if let result = scanResult {
                        scanResultSection(result)
                    }
                }
                .padding(.vertical)
            }
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .onChange(of: selectedPhoto) { loadAndScan() }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { data in
                    imageData = data
                    showingSourcePicker = false
                    scanImage(data)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Source Picker (Camera vs Library)

    private var sourcePickerSection: some View {
        VStack(spacing: 14) {
            Text("Scan a receipt")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
            Text("Take a photo or choose from your library. AI will extract the merchant, items, and total.")
                .font(.system(size: 15))
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Camera button
            Button { showingCamera = true } label: {
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

            // Photo library button
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
                .glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 16))
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 20)
    }

    private var photoPickerSection: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(TabAccent.home.color)
                Text("Select Receipt Photo")
                    .font(.headline)
                Text("Take a photo or choose from library")
                    .font(.caption)
                    .foregroundStyle(WarmPalette.ink3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(WarmPalette.ink1.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal)
    }

    // MARK: - Scan Results

    private func scanResultSection(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
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

            // Items
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

            // Category
            HStack {
                Text("Category").font(.subheadline.weight(.medium))
                Spacer()
                Text(result.category)
                    .font(.subheadline)
                    .padding(.horizontal, DesignTokens.Spacing.inset)
                    .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                    .background(AccentTheme.ocean.color.opacity(DesignTokens.Opacity.cardTint))
                    .clipShape(Capsule())
            }

            Toggle("Also add items to Pantry", isOn: $addToPantry).font(.subheadline)

            // Save
            Button { save() } label: {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Save Receipt\(addToPantry ? " & Stock Pantry" : "")")
                        .font(.headline).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(TabAccent.home.color)
            .controlSize(.large)
            .disabled(isSaving)

            // Retake
            Button {
                imageData = nil
                scanResult = nil
                showingSourcePicker = true
                selectedPhoto = nil
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

    private func loadAndScan() {
        guard let selectedPhoto else { return }
        showingSourcePicker = false
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
                try await api.saveScannedReceipt(result: result, addToPantry: addToPantry)
                dismiss()
            } catch {
                self.error = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void

        init(onCapture: @escaping (Data) -> Void) {
            self.onCapture = onCapture
        }

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
