import SwiftUI

struct AddPantryItemView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var itemName = ""
    @State private var category = "Other"
    @State private var location = "Pantry"
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date().addingTimeInterval(7 * 86400)
    @State private var addExpiryAlert = false
    @State private var isSaving = false
    @State private var error: String?

    let onSave: ([String: Any]) -> Void

    private let categories = ["Produce", "Dairy", "Meat", "Bakery", "Frozen", "Dry Goods", "Beverages", "Snacks", "Household", "Other"]
    private let locations = ["Fridge", "Freezer", "Pantry", "Counter"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $itemName)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }

                Section("Storage") {
                    Picker("Location", selection: $location) {
                        ForEach(locations, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField("Qty", text: $quantity)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        TextField("Unit (optional)", text: $unit)
                    }
                }

                Section("Expiry") {
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                        Toggle("Notify me the day before", isOn: $addExpiryAlert)
                        Text("If notifications are unavailable, the item still saves and the alert is skipped.")
                            .font(.caption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .pantry) }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .inlineError(error) { error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(itemName.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        var data: [String: Any] = [
            "item": itemName,
            "category": category,
            "location": location.lowercased(),
            "quantity": quantity
        ]
        if !unit.isEmpty { data["unit"] = unit }
        if hasExpiry {
            data["expiry_date"] = DateFormatter.isoDate.string(from: expiryDate)
        }

        onSave(data)
        if hasExpiry && addExpiryAlert {
            let authorized = await NotificationService.shared.ensurePermissionIfNeeded()
            if authorized {
                NotificationService.shared.schedulePantryExpiryAlert(
                    id: Int(Date().timeIntervalSince1970),
                    itemName: itemName,
                    expiryDate: DateFormatter.isoDate.string(from: expiryDate)
                )
            }
        }
        isSaving = false
        dismiss()
    }

}

#Preview {
    AddPantryItemView { _ in }
}
