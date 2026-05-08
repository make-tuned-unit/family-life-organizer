import SwiftUI

// MARK: - Server Response Models

struct ProjectResponse: Codable, Identifiable {
    let id: Int
    var name: String
    var budget: Double
    var total_spent: Double
    var expense_count: Int
    var created_by: String?
    var created_at: String?

    var remaining: Double { budget - total_spent }
    var progress: Double { budget > 0 ? total_spent / budget : 0 }
}

struct ProjectExpenseResponse: Codable, Identifiable {
    let id: Int
    var project_id: Int
    var description: String
    var amount: Double
    var category: String
    var notes: String?
    var created_at: String?
}

// MARK: - Storage (API-backed, shared between family members)

@Observable
final class BudgetProjectStore {
    var projects: [ProjectResponse] = []
    var isLoading = false
    var error: String?

    func loadAll(api: APIService) async {
        isLoading = true
        error = nil
        do {
            projects = try await api.fetchProjects()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addProject(name: String, budget: Double, api: APIService) async {
        do {
            let _ = try await api.addProject(["name": name, "budget": budget])
            await loadAll(api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addExpense(_ expense: [String: Any], to projectID: Int, api: APIService) async {
        do {
            let _ = try await api.addProjectExpense(projectId: projectID, expense: expense)
            await loadAll(api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteExpense(_ expenseID: Int, from projectID: Int, api: APIService) async {
        do {
            try await api.deleteProjectExpense(projectId: projectID, expenseId: expenseID)
            await loadAll(api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteProject(_ projectID: Int, api: APIService) async {
        do {
            try await api.deleteProject(id: projectID)
            await loadAll(api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Projects List View

struct BudgetProjectsView: View {
    @Environment(APIService.self) private var api
    @State private var store = BudgetProjectStore()
    @State private var showingNewProject = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(store.projects.count) PROJECTS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink3)
                            .tracking(0.4)
                        Text("Projects")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(WarmPalette.ink1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 16)

                if store.projects.isEmpty && !store.isLoading {
                    WarmEmptyState(
                        title: "No projects yet",
                        systemImage: "hammer.fill",
                        description: "Track spending on big projects like renovations, trips, or events"
                    )
                } else {
                    ForEach(store.projects) { project in
                        NavigationLink {
                            ProjectDetailView(store: store, projectID: project.id)
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 10)
                    }
                }

                // New project button
                Button { showingNewProject = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("New Project")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(TabAccent.home.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                }
                .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                .padding(.bottom, 40)
            }
        }
        .background { AmbientBackground(style: .expenses) }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.isLoading && store.projects.isEmpty { ProgressView() }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet { name, budget in
                Task { await store.addProject(name: name, budget: budget, api: api) }
            }
        }
        .refreshable { await store.loadAll(api: api) }
        .task { await store.loadAll(api: api) }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: ProjectResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AccentTheme.sage.color)
                    .frame(width: 32, height: 32)
                    .background(AccentTheme.sage.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("\(project.expense_count) expenses")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(project.total_spent).formatted())")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("of $\(Int(project.budget).formatted())")
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }
            }

            WarmProgressBar(
                progress: project.progress,
                color: projectProgressColor(project.progress)
            )
        }
        .padding(16)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

// MARK: - Project Detail

struct ProjectDetailView: View {
    let store: BudgetProjectStore
    let projectID: Int
    @Environment(APIService.self) private var api
    @State private var expenses: [ProjectExpenseResponse] = []
    @State private var showingAddExpense = false
    @State private var showingScanReceipt = false
    @State private var isLoading = false

    private var project: ProjectResponse? {
        store.projects.first { $0.id == projectID }
    }

    var body: some View {
        if let project {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero summary
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PROJECT BUDGET")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink3)
                            .tracking(0.4)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("$\(Int(project.total_spent).formatted())")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(WarmPalette.ink1)
                                .tracking(-0.88)
                            Text("of $\(Int(project.budget).formatted())")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                        WarmProgressBar(
                            progress: project.progress,
                            color: projectProgressColor(project.progress),
                            height: 10
                        )
                        .padding(.bottom, 12)

                        HStack {
                            Text("$\(Int(project.remaining).formatted()) remaining")
                                .font(.system(size: 13))
                                .foregroundStyle(WarmPalette.ink3)
                            Spacer()
                            Text(project.progress <= 1.0 ? "on track" : "over budget")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(project.progress <= 1.0 ? WarmPalette.good : WarmPalette.bad)
                        }
                    }
                    .padding(20)
                    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.cardLarge))
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                    // Expenses list
                    if !expenses.isEmpty {
                        WarmSectionHeader(title: "Expenses", trailing: "\(expenses.count)")
                            .padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                                if index > 0 { GlassDivider() }
                                ProjectExpenseRow(expense: expense) {
                                    Task { await store.deleteExpense(expense.id, from: projectID, api: api); await loadExpenses() }
                                }
                            }
                        }
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    } else if !isLoading {
                        WarmEmptyState(
                            title: "No expenses yet",
                            systemImage: "receipt",
                            description: "Add your first expense to start tracking"
                        )
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAddExpense = true } label: {
                            Label("Add Manually", systemImage: "square.and.pencil")
                        }
                        Button { showingScanReceipt = true } label: {
                            Label("Scan Receipt", systemImage: "camera.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(WarmPalette.ink2)
                    }
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddProjectExpenseSheet(projectID: projectID) { expenseData in
                    Task {
                        await store.addExpense(expenseData, to: projectID, api: api)
                        await loadExpenses()
                    }
                }
            }
            .sheet(isPresented: $showingScanReceipt) {
                ReceiptScannerView(
                    projectId: projectID,
                    projectName: project.name,
                    onProjectExpenseSaved: {
                        await store.loadAll(api: api)
                        await loadExpenses()
                    }
                )
            }
            .task { await loadExpenses() }
        }
    }

    private func loadExpenses() async {
        isLoading = true
        do {
            expenses = try await api.fetchProjectExpenses(projectId: projectID)
        } catch {}
        isLoading = false
    }
}

// MARK: - Expense Row

struct ProjectExpenseRow: View {
    let expense: ProjectExpenseResponse
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.description)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                HStack(spacing: 6) {
                    Text(expense.category)
                    if let dateStr = expense.created_at {
                        Text(formattedDate(dateStr))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            }
            Spacer()
            Text("$\(expense.amount, specifier: "%.2f")")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WarmPalette.ink1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let prefix = String(raw.prefix(10)) // "YYYY-MM-DD"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: prefix) else { return prefix }
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    let onCreate: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var budgetText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $name)
                    TextField("Budget", text: $budgetText)
                        .keyboardType(.decimalPad)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let budget = Double(budgetText) ?? 0
                        onCreate(name, budget)
                        dismiss()
                    }
                    .disabled(name.isEmpty || budgetText.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Expense Sheet

struct AddProjectExpenseSheet: View {
    let projectID: Int
    let onAdd: ([String: Any]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var amountText = ""
    @State private var category = "Materials"
    @State private var notes = ""

    private let categories = ["Materials", "Labour", "Tools", "Permits", "Delivery", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("What was it for?", text: $description)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .expenses) }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let amount = Double(amountText) ?? 0
                        var data: [String: Any] = [
                            "description": description,
                            "amount": amount,
                            "category": category
                        ]
                        if !notes.isEmpty { data["notes"] = notes }
                        onAdd(data)
                        dismiss()
                    }
                    .disabled(description.isEmpty || amountText.isEmpty)
                }
            }
        }
    }
}

// MARK: - Helpers

private func projectProgressColor(_ progress: Double) -> Color {
    if progress > 1.0 { return WarmPalette.bad }
    if progress > 0.85 { return AccentTheme.saffron.color }
    return AccentTheme.sage.color
}

#Preview {
    NavigationStack {
        BudgetProjectsView()
    }
    .environment(APIService())
}
