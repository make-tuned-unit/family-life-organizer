import SwiftUI

struct EditPantryItemView: View {
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    let item: PantryItemResponse
    let onSaved: () -> Void

    @State private var itemName: String
    @State private var category: String
    @State private var location: String
    @State private var quantity: String
    @State private var unit: String
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var addExpiryAlert = false
    @State private var isSaving = false
    @State private var error: String?

    private let categories = ["Produce", "Dairy", "Meat", "Bakery", "Frozen", "Dry Goods", "Beverages", "Snacks", "Household", "Other"]
    private let locations = ["Fridge", "Freezer", "Pantry", "Counter"]

    init(item: PantryItemResponse, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved

        _itemName = State(initialValue: item.item)
        _category = State(initialValue: item.category ?? "Other")
        _location = State(initialValue: (item.location ?? "pantry").capitalized)
        _quantity = State(initialValue: item.quantity ?? "1")
        _unit = State(initialValue: item.unit ?? "")
        _hasExpiry = State(initialValue: item.expiry_date != nil)

        _expiryDate = State(initialValue: DateFormatter.isoDate.date(from: item.expiry_date ?? "") ?? Date().addingTimeInterval(7 * 86400))
    }

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
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t save changes", isPresented: errorAlertIsPresented) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "An unexpected error occurred.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(itemName.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
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

        Task {
            do {
                try await api.updatePantryItem(id: item.id, data: data)
                if hasExpiry && addExpiryAlert {
                    let authorized = await NotificationService.shared.ensurePermissionIfNeeded()
                    if authorized {
                        NotificationService.shared.schedulePantryExpiryAlert(
                            id: item.id,
                            itemName: itemName,
                            expiryDate: DateFormatter.isoDate.string(from: expiryDate)
                        )
                    }
                }
                onSaved()
                dismiss()
            } catch let saveError {
                error = saveError.localizedDescription
                isSaving = false
            }
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
    EditPantryItemView(
        item: PantryItemResponse(
            id: 1, item: "Milk", category: "Dairy",
            location: "fridge", quantity: "1", unit: "gallon",
            expiry_date: "2026-03-28", added_by: "jesse", created_at: nil
        ),
        onSaved: {}
    )
    .environment(APIService())
}
