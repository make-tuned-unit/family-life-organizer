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
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .pantry) }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        save()
                        dismiss()
                    }
                    .disabled(itemName.isEmpty)
                }
            }
        }
    }

    private func save() {
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
    }
}

#Preview {
    AddPantryItemView { _ in }
}
