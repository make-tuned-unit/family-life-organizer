import SwiftUI
import PhotosUI

struct AddReceiptView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var merchant = ""
    @State private var category = "Groceries"
    @State private var date = Date()
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false

    private let categories = ["Groceries", "Dining Out", "Gas/Transport", "Household", "Health", "Entertainment", "Kids", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Merchant", text: $merchant)

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }

                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(selectedPhoto == nil ? "Attach Receipt Photo" : "Photo Selected", systemImage: selectedPhoto == nil ? "camera" : "checkmark.circle.fill")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle("Add Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(amount.isEmpty || merchant.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let amountValue = Double(amount) else { return }
        isSaving = true

        let body: [String: Any] = [
            "amount": amountValue,
            "merchant": merchant,
            "date": DateFormatter.isoDate.string(from: date),
            "category": category,
            "notes": notes.isEmpty ? NSNull() : notes,
            "processed_by": "manual"
        ]

        Task {
            do {
                try await api.addReceipt(body)
                dismiss()
            } catch {
                isSaving = false
            }
        }
    }
}

#Preview {
    AddReceiptView()
        .environment(APIService())
}
