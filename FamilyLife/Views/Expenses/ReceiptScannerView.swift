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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo picker
                    if imageData == nil {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            VStack(spacing: 16) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.teal)
                                Text("Select Receipt Photo")
                                    .font(.headline)
                                Text("Take a photo or choose from library")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal)
                    }

                    // Scanning state
                    if isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Scanning receipt with AI...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.large)
                    }

                    // Error
                    if let error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(TabAccent.expenses.color.opacity(DesignTokens.Opacity.cardTint)) // DS-05: replaced raw opacity fill
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Scan results
                    if let result = scanResult {
                        VStack(alignment: .leading, spacing: 16) {
                            // Summary
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(result.merchant)
                                        .font(.headline)
                                    Text(result.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("$\(result.total, specifier: "%.2f")")
                                    .font(.title2.bold())
                                    .foregroundStyle(.teal)
                            }
                            .padding()
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Items
                            Text("Items Found")
                                .font(.headline)

                            ForEach(Array(result.items.enumerated()), id: \.offset) { idx, item in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(item.name)
                                        .font(.subheadline)
                                    Spacer()
                                    if let price = item.price {
                                        Text("$\(price, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                            }

                            // Category
                            HStack {
                                Text("Category")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(result.category)
                                    .font(.subheadline)
                                    .padding(.horizontal, DesignTokens.Spacing.inset)
                                    .padding(.vertical, DesignTokens.Spacing.chipVerticalPadding)
                                    .background(BadgeSemantic.info.color.opacity(DesignTokens.Opacity.cardTint)) // DS-05: replaced raw opacity fill
                                    .clipShape(Capsule())
                            }

                            // Add to pantry toggle
                            Toggle("Also add items to Pantry", isOn: $addToPantry)
                                .font(.subheadline)

                            // Save button
                            Button {
                                save()
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Save Receipt\(addToPantry ? " & Stock Pantry" : "")")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.large)
                            .disabled(isSaving)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) {
                loadAndScan()
            }
        }
    }

    private func loadAndScan() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            imageData = data
            isScanning = true
            error = nil

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

// API response types for receipt scanning
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
