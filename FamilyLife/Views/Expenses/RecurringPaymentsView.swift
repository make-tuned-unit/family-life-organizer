import SwiftUI

// MARK: - Model (GET /api/recurring-payments)

struct RecurringPayment: Codable, Identifiable {
    let id: Int
    var name: String
    var amount: Double
    var category: String?
    var frequency: String?
    var due_day: Int?
    var due_date: String?
    var autopay: Int?
    var icon: String?
    var notes: String?

    var isAutopay: Bool { (autopay ?? 0) == 1 }

    var monthlyEquivalent: Double {
        switch frequency {
        case "weekly": return amount * 52 / 12
        case "yearly": return amount / 12
        default: return amount
        }
    }

    var cadenceLabel: String {
        switch frequency {
        case "weekly": return "Weekly"
        case "yearly": return "Yearly"
        default:
            if let d = due_day { return "Monthly \u{00B7} due \(Self.ordinal(d))" }
            return "Monthly"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Categories / presets

enum RecurringCategory: String, CaseIterable, Identifiable {
    case housing = "Housing", utilities = "Utilities", insurance = "Insurance"
    case transport = "Transport", subscriptions = "Subscriptions", debt = "Debt", other = "Other"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .housing: return "house.fill"
        case .utilities: return "bolt.fill"
        case .insurance: return "shield.fill"
        case .transport: return "car.fill"
        case .subscriptions: return "play.tv.fill"
        case .debt: return "creditcard.fill"
        case .other: return "dollarsign.circle.fill"
        }
    }

    static func icon(for category: String?) -> String {
        guard let category, let match = allCases.first(where: { $0.rawValue.caseInsensitiveCompare(category) == .orderedSame }) else {
            return RecurringCategory.other.icon
        }
        return match.icon
    }
}

struct RecurringPreset { let name: String; let category: RecurringCategory }
let recurringPresets: [RecurringPreset] = [
    .init(name: "Rent", category: .housing),
    .init(name: "Mortgage", category: .housing),
    .init(name: "Netflix", category: .subscriptions),
    .init(name: "Spotify", category: .subscriptions),
    .init(name: "Car payment", category: .transport),
    .init(name: "Insurance", category: .insurance),
]

// MARK: - Store

@MainActor
@Observable
final class RecurringPaymentsStore {
    var items: [RecurringPayment] = []
    var isLoading = false
    var error: String?

    var monthlyTotal: Double { items.reduce(0) { $0 + $1.monthlyEquivalent } }

    func load(api: APIService) async {
        isLoading = true
        defer { isLoading = false }
        do { items = try await api.fetchRecurringPayments() }
        catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func delete(api: APIService, id: Int) async {
        do { try await api.deleteRecurringPayment(id: id); await load(api: api) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - List View

struct RecurringPaymentsView: View {
    @Environment(APIService.self) private var api
    @State private var store = RecurringPaymentsStore()
    @State private var editing: RecurringPayment?
    @State private var showingAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                totalCard
                if store.items.isEmpty && !store.isLoading {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.items) { item in
                            Button { editing = item } label: { RecurringRow(item: item) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await store.delete(api: api, id: item.id) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 14)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .foregroundStyle(WarmPalette.ink2)
            }
        }
        .sheet(isPresented: $showingAdd) {
            RecurringPaymentEditor(existing: nil) { await store.load(api: api) }
        }
        .sheet(item: $editing) { item in
            RecurringPaymentEditor(existing: item) { await store.load(api: api) }
        }
        .task { await store.load(api: api) }
        .refreshable { await store.load(api: api) }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MONTHLY COMMITTED")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3).tracking(0.4)
            Text("$\(Int(store.monthlyTotal).formatted())")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(WarmPalette.ink1).tracking(-0.7)
            Text("\(store.items.count) recurring payment\(store.items.count == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(WarmPalette.ink3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.cardLarge))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 32)).foregroundStyle(WarmPalette.ink4)
            Text("No recurring payments yet")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(WarmPalette.ink2)
            Text("Add rent, subscriptions, insurance and more to see your fixed monthly costs.")
                .font(.system(size: 13)).foregroundStyle(WarmPalette.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

private struct RecurringRow: View {
    let item: RecurringPayment

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon ?? RecurringCategory.icon(for: item.category))
                .font(.system(size: 16))
                .foregroundStyle(AccentTheme.ocean.color)
                .frame(width: 40, height: 40)
                .background(AccentTheme.ocean.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    if item.isAutopay {
                        Text("Autopay")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AccentTheme.sage.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AccentTheme.sage.color.opacity(0.15), in: Capsule())
                    }
                }
                Text(item.cadenceLabel)
                    .font(.system(size: 12)).foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            Text("$\(Int(item.amount).formatted())")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
        }
        .padding(14)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Add / Edit Editor

struct RecurringPaymentEditor: View {
    let existing: RecurringPayment?
    let onSave: () async -> Void

    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amount = ""
    @State private var category: RecurringCategory = .housing
    @State private var frequency = "monthly"
    @State private var dueDay = 1
    @State private var autopay = false
    @State private var notes = ""
    @State private var saving = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(amount) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("Quick add") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recurringPresets, id: \.name) { preset in
                                    Button {
                                        name = preset.name
                                        category = preset.category
                                    } label: {
                                        Text(preset.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(AccentTheme.ocean.color.opacity(0.12), in: Capsule())
                                            .foregroundStyle(AccentTheme.ocean.color)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Name (e.g. Rent)", text: $name)
                    HStack {
                        Text("$")
                        TextField("0", text: $amount).keyboardType(.decimalPad)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(RecurringCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        Text("Monthly").tag("monthly")
                        Text("Weekly").tag("weekly")
                        Text("Yearly").tag("yearly")
                    }
                    if frequency == "monthly" {
                        Picker("Due day", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { Text(RecurringPayment.ordinal($0)).tag($0) }
                        }
                    }
                    Toggle("Autopay", isOn: $autopay)
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            Task { await deleteSelf() }
                        } label: { Text("Delete payment") }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || saving)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let e = existing else { return }
        name = e.name
        amount = String(format: "%g", e.amount)
        category = RecurringCategory(rawValue: e.category ?? "") ?? .other
        frequency = e.frequency ?? "monthly"
        dueDay = e.due_day ?? 1
        autopay = e.isAutopay
        notes = e.notes ?? ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var data: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "amount": Double(amount) ?? 0,
            "category": category.rawValue,
            "frequency": frequency,
            "autopay": autopay,
            "icon": category.icon,
            "notes": notes,
        ]
        if frequency == "monthly" { data["due_day"] = dueDay }
        do {
            if let e = existing {
                try await api.updateRecurringPayment(id: e.id, data: data)
            } else {
                try await api.addRecurringPayment(data)
            }
            await onSave()
            dismiss()
        } catch {
            // surfaced on next load; keep editor open
        }
    }

    private func deleteSelf() async {
        guard let e = existing else { return }
        do { try await api.deleteRecurringPayment(id: e.id); await onSave(); dismiss() }
        catch { }
    }
}
