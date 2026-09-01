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
    @State private var selectedPhotos: [PhotosPickerItem] = []
    /// Library photos still waiting to be scanned. A camera capture never
    /// queues — that flow stays one shot at a time.
    @State private var photoQueue: [Data] = []
    @State private var queueTotal = 0     // batch size, for "Receipt i of N"
    @State private var queueIndex = 0     // 1-based position in the batch
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
    @State private var showingReceiptDisclosure = false
    @State private var pendingScanData: Data?

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

                    if queueTotal > 1 {
                        batchProgressChip
                    }

                    if isScanning {
                        FLLoadingState(message: queueTotal > 1
                            ? "Scanning receipt \(queueIndex) of \(queueTotal)..."
                            : "Scanning receipt with AI...")
                    }

                    if let error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AccentTheme.saffron.color)
                            Text(error).font(.flSubheadline)
                        }
                        .padding()
                        .background(TabAccent.expenses.color.opacity(DesignTokens.Opacity.cardTint))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    if cameraPermissionDenied {
                        VStack(spacing: 8) {
                            Text("Camera access denied")
                                .font(.flSubheadline.weight(.semibold))
                            Text("Go to Settings > Kinrows to enable camera access.")
                                .font(.flCaption)
                                .foregroundStyle(WarmPalette.ink3)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.flSubheadline.weight(.medium))
                        }
                        .padding()
                        .flCard()
                        .padding(.horizontal)
                    }

                    if let result = scanResult {
                        scanResultSection(result)
                    } else if imageData != nil, !isScanning, error != nil {
                        // A scan failed mid-flow — offer a way forward instead
                        // of a dead end (retry, or move on through the batch).
                        scanFailureActions
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
            .onChange(of: selectedPhotos) { loadBatchAndScan() }
            .sheet(isPresented: $showingCamera) {
                CameraView { data in
                    imageData = data
                    scanImage(data)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingReceiptDisclosure) {
                AIDisclosureView(
                    title: "Scan with AI",
                    detail: "Scanning sends a photo of your receipt to **Claude by Anthropic** to read the merchant, items, and total.",
                    sentDescription: "The receipt photo is sent to Anthropic's API to extract the details",
                    onAccept: {
                        AIConsentManager.grantReceipt()
                        showingReceiptDisclosure = false
                        if let data = pendingScanData { pendingScanData = nil; scanImage(data) }
                    },
                    onDecline: {
                        showingReceiptDisclosure = false
                        pendingScanData = nil
                    }
                )
            }
        }
        // Match the sheet's outer presentation surface to the scanner content;
        // otherwise the system's default white surface appears as side strips.
        .presentationBackground { AmbientBackground(style: .expenses) }
    }

    // MARK: - Source Picker

    private var sourcePickerSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(TabAccent.expenses.color)
                .padding(.bottom, 4)

            Text(isProjectMode ? "Scan receipt for \(projectName ?? "project")" : "Scan a receipt")
                .font(.flTitle)
                .foregroundStyle(WarmPalette.ink1)
            Text("Take a photo, or pick several receipts from your library at once — AI extracts the merchant, items, and total from each.")
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Camera button
            Button { requestCameraAndShow() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                    Text("Take Photo")
                }
            }
            .buttonStyle(.flCTA)
            .padding(.horizontal, 22)

            // Photo library — multi-select so a stack of receipts is one trip
            // to the picker, then reviewed and saved one after another.
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20))
                        Text("Choose from Library")
                            .font(.flHeadline)
                    }
                    .foregroundStyle(WarmPalette.ink1)
                    Text("Select up to 10 receipts")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .flCard()
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 20)
    }

    /// "Receipt 2 of 5 · 1 saved" — batch position while working a stack.
    private var batchProgressChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TabAccent.expenses.color)
            Text("Receipt \(max(queueIndex, 1)) of \(queueTotal)")
                .font(.flFootnote.weight(.semibold))
                .foregroundStyle(WarmPalette.ink1)
            if savedCount > 0 {
                Text("· \(savedCount) saved")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.good)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(WarmPalette.cardSurface, in: Capsule())
    }

    /// Shown when a scan errored: retry the same photo, or move on.
    private var scanFailureActions: some View {
        VStack(spacing: 10) {
            Button {
                if let data = imageData { scanImage(data) }
            } label: {
                Text("Try Again")
            }
            .buttonStyle(.flCTA(fill: TabAccent.home.color))

            Button {
                if photoQueue.isEmpty { resetForNextScan() } else { advanceQueue() }
            } label: {
                Text(photoQueue.isEmpty ? "Choose a Different Photo" : "Skip This Receipt")
                    .font(.flSubheadline.weight(.medium))
                    .foregroundStyle(WarmPalette.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Scan Results

    private func scanResultSection(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Editable header — merchant, date, total
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Merchant").font(.flCaption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                        TextField("Store name", text: $editableMerchant)
                            .font(.flHeadline)
                            .foregroundStyle(WarmPalette.ink1)
                    }
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Date").font(.flCaption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                            if dateNeedsAttention {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.flCaption2)
                                    .foregroundStyle(AccentTheme.saffron.color)
                            }
                        }
                        TextField("YYYY-MM-DD", text: $editableDate)
                            .font(.flSubheadline)
                            .foregroundStyle(dateNeedsAttention ? WarmPalette.bad : WarmPalette.ink2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Total").font(.flCaption.weight(.medium)).foregroundStyle(WarmPalette.ink3)
                        HStack(spacing: 2) {
                            Text("$")
                                .font(.flStat)
                                .foregroundStyle(TabAccent.home.color)
                            TextField("0.00", text: $editableTotal)
                                .font(.flStat)
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
                        .font(.flSubheadline.weight(.medium))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AccentTheme.sage.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Items Found").font(.flHeadline)
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WarmPalette.good)
                    Text(item.name).font(.flSubheadline)
                    Spacer()
                    if let price = item.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.flSubheadline).foregroundStyle(WarmPalette.ink3)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
            }

            HStack {
                Text(isProjectMode ? "Project" : "Category").font(.flSubheadline.weight(.medium))
                Spacer()
                if isProjectMode {
                    Text(projectName ?? "Project")
                        .font(.flSubheadline)
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
                        .font(.flSubheadline.weight(.medium))
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
                        Text(queueTotal > 1 ? "That's the whole stack — \(savedCount) saved!" : "Receipt saved!")
                            .font(.flHeadline)
                            .foregroundStyle(WarmPalette.good)
                        Spacer()
                    }
                    Text("$\(editableTotal) → \(selectedCategory) • \(formattedSavedMonth)")
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .padding()
                .background(WarmPalette.good.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    resetForNextScan()
                } label: {
                    Text("Scan Another Receipt")
                }
                .buttonStyle(.flCTA(fill: TabAccent.home.color))

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.flSubheadline.weight(.medium))
                        .foregroundStyle(WarmPalette.ink3)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Not yet saved — show save button
                Button {
                    Task { await saveReceipt() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(isProjectMode ? "Add to Project" : "Save Receipt")
                    }
                }
                .buttonStyle(.flCTA(fill: isProjectMode ? AccentTheme.sage.color : TabAccent.home.color))
                .disabled(isSaving || editableTotal.isEmpty || editableMerchant.isEmpty)

                Button {
                    if photoQueue.isEmpty { resetForNextScan() } else { advanceQueue() }
                } label: {
                    Text(photoQueue.isEmpty ? "Discard & Scan Again" : "Skip This Receipt")
                        .font(.flSubheadline.weight(.medium))
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
        clearScanFields()
        imageData = nil
        selectedPhotos = []
        photoQueue = []
        queueTotal = 0
        queueIndex = 0
    }

    /// Clears the per-receipt state only — batch bookkeeping survives so the
    /// next queued photo scans into a clean sheet.
    private func clearScanFields() {
        scanResult = nil
        error = nil
        currentScanSaved = false
        selectedCategory = "Other"
        editableTotal = ""
        editableMerchant = ""
        editableDate = ""
    }

    /// Pop the next library photo off the queue and scan it.
    private func advanceQueue() {
        guard !photoQueue.isEmpty else { return }
        clearScanFields()
        let next = photoQueue.removeFirst()
        queueIndex += 1
        imageData = next
        scanImage(next)
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

    private func loadBatchAndScan() {
        guard !selectedPhotos.isEmpty else { return }
        let items = selectedPhotos
        selectedPhotos = []
        Task {
            var images: [Data] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                // PhotosPicker can return HEIC/PNG data. Normalize library photos
                // to JPEG so the server/vision provider receive a stable contract.
                images.append(normalizedScanImageData(data) ?? data)
            }
            guard !images.isEmpty else {
                error = "Couldn't load those photos — try picking them again."
                return
            }
            queueTotal = images.count
            queueIndex = 0
            photoQueue = images
            advanceQueue()
        }
    }

    private func normalizedScanImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.85)
    }

    private func scanImage(_ data: Data) {
        // Receipt scanning sends the image to cloud vision AI — respect the toggle.
        guard cloudAIEnabled else {
            error = "Cloud AI is off. Turn it on in Settings → Privacy to scan receipts, or enter the receipt manually."
            return
        }
        // First-use disclosure (5.1.2(i)): a photo of financial data goes to
        // Anthropic. Hold the image and show consent; the scan resumes on accept.
        guard AIConsentManager.hasReceiptConsent else {
            pendingScanData = data
            showingReceiptDisclosure = true
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                let detail = error.localizedDescription
                self.error = detail == "Server error (503)" || detail.localizedCaseInsensitiveContains("temporarily unavailable")
                    ? "Receipt scanning is temporarily unavailable. Try adding manually."
                    : "Could not scan receipt: \(detail)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                savedCount += 1
                Task.detached { await onProjectExpenseSaved?() }
                if photoQueue.isEmpty {
                    currentScanSaved = true
                } else {
                    // More receipts waiting — straight on to the next one.
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    advanceQueue()
                }
            } else {
                let itinId = selectedCategory == "Trip" ? selectedItinerary?.id : nil
                let savedId = try await api.saveScannedReceipt(result: result, category: selectedCategory, notes: itemDetail, itineraryId: itinId)
                guard savedId > 0 else {
                    self.error = "Receipt save did not return a valid id. Try again."
                    return
                }
                savedCount += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await onReceiptSaved?()
                if photoQueue.isEmpty {
                    currentScanSaved = true
                } else {
                    // More receipts waiting — straight on to the next one.
                    advanceQueue()
                }
            }
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
            // Same rules as total: "$1,299.00" must parse, not vanish.
            price = Double(s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        } else {
            price = nil
        }
    }
}

#Preview {
    ReceiptScannerView()
        .environment(APIService())
}
