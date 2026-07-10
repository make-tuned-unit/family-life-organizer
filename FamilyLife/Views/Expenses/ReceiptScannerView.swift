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
    var onReceiptSaved: (() async -> Void)?

    @AppStorage("cloudAIEnabled") private var cloudAIEnabled = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var scanResult: ScanResult?
    @State private var isScanning = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingCamera = false
    @State private var cameraPermissionDenied = false
    @State private var savedCount = 0
    @State private var currentScanSaved = false
    @State private var selectedCategory = "Other"
    @State private var categories = defaultBudgetCategories
    @State private var editableTotal = ""
    @State private var editableMerchant = ""
    @State private var editableDate = ""
    @State private var selectedItinerary: ItineraryResponse?
    @State private var itineraries: [ItineraryResponse] = []

    private var isProjectMode: Bool { projectId != nil }

    private var dateNeedsAttention: Bool {
        guard !editableDate.isEmpty else { return false }
        let parts = editableDate.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return true }
        let cal = Calendar.current
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        // Flag if date is more than 2 months from current month
        let monthDiff = abs((currentYear * 12 + currentMonth) - (year * 12 + month))
        return monthDiff > 2
    }

    private var formattedSavedMonth: String {
        // Parse the YYYY-MM-DD date and format as "Month YYYY"
        let parts = editableDate.split(separator: "-")
        guard parts.count >= 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return editableDate
        }
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(year)"
    }
    private static let defaultBudgetCategories = ["Groceries", "Dining Out", "Gas/Transport", "Household", "Health", "Pets", "Entertainment", "Kids", "Trip", "Other"]

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
            .task {
                await loadBudgetCategories()
                itineraries = (try? await api.fetchItineraries()) ?? []
            }
            .onChange(of: selectedPhoto) { loadAndScan() }
            .sheet(isPresented: $showingCamera) {
                CameraView { data in
                    imageData = data
                    scanImage(data)
                }
                .ignoresSafeArea()
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
            // Editable header — merchant, date, total
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Merchant").font(.caption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                        TextField("Store name", text: $editableMerchant)
                            .font(.headline)
                            .foregroundStyle(WarmPalette.ink1)
                    }
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Date").font(.caption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                            if dateNeedsAttention {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AccentTheme.saffron.color)
                            }
                        }
                        TextField("YYYY-MM-DD", text: $editableDate)
                            .font(.subheadline)
                            .foregroundStyle(dateNeedsAttention ? WarmPalette.bad : WarmPalette.ink2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Total").font(.caption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                        HStack(spacing: 2) {
                            Text("$")
                                .font(.title2.bold())
                                .foregroundStyle(TabAccent.home.color)
                            TextField("0.00", text: $editableTotal)
                                .font(.title2.bold())
                                .foregroundStyle(TabAccent.home.color)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                        }
                    }
                }
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
                if isProjectMode {
                    Text(projectName ?? "Project")
                        .font(.subheadline)
                        .padding(.horizontal, DesignTokens.Spacing.inset)
                        .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                        .background(AccentTheme.sage.color.opacity(DesignTokens.Opacity.cardTint))
                        .clipShape(Capsule())
                } else {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(TabAccent.expenses.color)
                }
            }

            if selectedCategory == "Trip" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Which trip?")
                        .font(.subheadline.weight(.medium))
                    ForEach(itineraries) { itin in
                        Button {
                            selectedItinerary = itin
                        } label: {
                            HStack {
                                Text(itin.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedItinerary?.id == itin.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AccentTheme.ocean.color)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if currentScanSaved {
                // Confirmed saved — show success state with details
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(WarmPalette.good)
                        Text("Receipt saved!")
                            .font(.headline)
                            .foregroundStyle(WarmPalette.good)
                        Spacer()
                    }
                    Text("$\(editableTotal) → \(selectedCategory) • \(formattedSavedMonth)")
                        .font(.subheadline)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding()
                .background(WarmPalette.good.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    resetForNextScan()
                } label: {
                    Text("Scan Another Receipt")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TabAccent.home.color)
                .controlSize(.large)

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WarmPalette.ink3)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Not yet saved — show save button
                Button {
                    Task { await saveReceipt() }
                } label: {
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
                .disabled(isSaving || editableTotal.isEmpty || editableMerchant.isEmpty)

                Button {
                    resetForNextScan()
                } label: {
                    Text("Discard & Scan Again")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WarmPalette.ink3)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isSaving)
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
        currentScanSaved = false
        selectedCategory = "Other"
        editableTotal = ""
        editableMerchant = ""
        editableDate = ""
    }

    private func loadBudgetCategories() async {
        guard !isProjectMode else { return }
        guard let remoteCategories = try? await api.fetchBudgetCategories() else { return }
        var merged = Self.defaultBudgetCategories
        for name in remoteCategories.map(\.name) where !merged.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            merged.append(name)
        }
        categories = merged
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
        // Receipt scanning sends the image to cloud vision AI — respect the toggle.
        guard cloudAIEnabled else {
            error = "Cloud AI is off. Turn it on in Settings → Privacy to scan receipts, or enter the receipt manually."
            return
        }
        isScanning = true
        error = nil
        currentScanSaved = false
        Task {
            do {
                let result = try await api.scanReceipt(imageData: data)
                scanResult = result
                // Populate editable fields from scan
                editableMerchant = result.merchant
                editableDate = result.date
                editableTotal = String(format: "%.2f", result.total)
                let category = normalizedCategory(for: result)
                if !categories.contains(where: { $0.localizedCaseInsensitiveCompare(category) == .orderedSame }) {
                    categories.append(category)
                    categories.sort()
                }
                selectedCategory = category
            } catch {
                self.error = "Could not scan receipt. Try adding manually."
            }
            isScanning = false
        }
    }

    private func saveReceipt() async {
        guard !isSaving else { return }
        guard var result = scanResult else { return }
        guard !currentScanSaved else { return }

        // Apply user edits to the result
        let parsedTotal = Double(editableTotal) ?? result.total
        result.total = parsedTotal
        result.merchant = editableMerchant.isEmpty ? result.merchant : editableMerchant
        result.date = editableDate.isEmpty ? result.date : editableDate
        scanResult = result

        isSaving = true
        defer { isSaving = false }

        do {
            let itemDetail = result.items.map { item in
                if let price = item.price {
                    return "\(item.name) — $\(String(format: "%.2f", price))"
                }
                return item.name
            }.joined(separator: "\n")

            if let projectId {
                let expenseData: [String: Any] = [
                    "description": result.merchant,
                    "amount": result.total,
                    "category": projectName ?? "General",
                    "notes": "\(selectedCategory) receipt\n\(itemDetail)"
                ]
                let _ = try await api.addProjectExpense(projectId: projectId, expense: expenseData)
                currentScanSaved = true
                savedCount += 1
                Task.detached { await onProjectExpenseSaved?() }
            } else {
                let itinId = selectedCategory == "Trip" ? selectedItinerary?.id : nil
                let savedId = try await api.saveScannedReceipt(result: result, category: selectedCategory, notes: itemDetail, itineraryId: itinId)
                guard savedId > 0 else {
                    self.error = "Receipt save did not return a valid id. Try again."
                    return
                }
                currentScanSaved = true
                savedCount += 1
                await onReceiptSaved?()
            }
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func normalizedCategory(for result: ScanResult) -> String {
        let scanned = result.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownCategory = categories.first { $0.localizedCaseInsensitiveCompare(scanned) == .orderedSame }
        let fallback = knownCategory ?? (scanned.isEmpty ? "Other" : scanned)
        let text = ([result.merchant, scanned] + result.items.map(\.name)).joined(separator: " ").lowercased()

        if text.contains("shoe")
            || text.contains("sneaker")
            || text.contains("kids")
            || text.contains("child")
            || text.contains("children")
            || text.contains("youth")
            || text.contains("school") {
            return categoryNamed("Kids") ?? fallback
        }

        return categoryNamed(fallback) ?? fallback
    }

    private func categoryNamed(_ name: String) -> String? {
        categories.first { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
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
    var merchant: String
    var date: String
    var total: Double
    var category: String
    var items: [ScanItem]
}

// The scan endpoint returns raw AI-extracted JSON — any key may be missing or
// mistyped (total as "$42.10"). Decode leniently so a scan never hard-fails;
// the review sheet lets the user correct whatever the AI got wrong.
extension ScanResult {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        merchant = (try? c.decode(String.self, forKey: .merchant)) ?? "Unknown"
        date = (try? c.decode(String.self, forKey: .date))
            ?? DateFormatter.isoDate.string(from: Date())
        category = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        items = (try? c.decode([ScanItem].self, forKey: .items)) ?? []
        if let d = try? c.decode(Double.self, forKey: .total) {
            total = d
        } else if let s = try? c.decode(String.self, forKey: .total),
                  let d = Double(s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) {
            total = d
        } else {
            total = 0
        }
    }
}

struct ScanItem: Codable {
    let name: String
    let price: Double?
    let quantity: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Item"
        quantity = try? c.decode(String.self, forKey: .quantity)
        if let d = try? c.decode(Double.self, forKey: .price) {
            price = d
        } else if let s = try? c.decode(String.self, forKey: .price) {
            price = Double(s.replacingOccurrences(of: "$", with: ""))
        } else {
            price = nil
        }
    }
}

#Preview {
    ReceiptScannerView()
        .environment(APIService())
}
