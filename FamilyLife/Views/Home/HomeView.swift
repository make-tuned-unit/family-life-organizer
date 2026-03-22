import SwiftUI

struct HomeView: View {
    @Environment(APIService.self) private var api
    @Environment(AuthService.self) private var auth
    @State private var viewModel = HomeViewModel()
    @State private var showingAddTask = false
    @State private var showingFood = false
    @State private var showingSettings = false
    @State private var showingCalendar = false
    @State private var showingPantry = false
    @State private var showingExpenses = false
    @State private var showingTrips = false
    @State private var showingRivalries = false
    @State private var showingDecisions = false
    @State private var showingGifts = false
    @State private var todaySteps: Int?
    @State private var activeTrips: [TripResponse] = []
    @State private var healthKit = HealthKitManager()

    private let greeting: String = {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Greeting
                greetingHeader

                // At-a-glance stats
                statsRow

                // Live activity: steps, location, upcoming
                liveActivitySection

                // Feature hub
                featureGrid

                // Today's schedule
                todaySection

                // Active tasks
                tasksSection

                // Grocery preview
                grocerySection
            }
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .refreshable {
            await viewModel.loadAll(api: api)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTask = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView { task in
                Task { await viewModel.addTask(task, api: api) }
            }
        }
        .sheet(isPresented: $showingFood) {
            NavigationStack {
                FoodKitchenView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                CalendarView()
            }
        }
        .sheet(isPresented: $showingPantry) {
            NavigationStack {
                PantryView()
            }
        }
        .sheet(isPresented: $showingExpenses) {
            NavigationStack {
                ExpensesView()
            }
        }
        .sheet(isPresented: $showingTrips) {
            NavigationStack {
                TripsView()
            }
        }
        .sheet(isPresented: $showingRivalries) {
            NavigationStack {
                RivalriesView()
            }
        }
        .sheet(isPresented: $showingDecisions) {
            NavigationStack {
                DecisionsView()
            }
        }
        .sheet(isPresented: $showingGifts) {
            NavigationStack {
                GiftsView()
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.summary == nil {
                ProgressView()
            }
        }
        .task {
            await viewModel.loadAll(api: api)
            await loadLiveData()
        }
    }

    private func loadLiveData() async {
        // Steps from HealthKit (guard for simulator)
        if healthKit.isAvailable {
            if await healthKit.requestStepAuthorization() {
                let start = Calendar.current.startOfDay(for: Date())
                let steps = await healthKit.fetchSteps(from: start, to: Date())
                todaySteps = Int(steps)
            }
        }
        // Active trips
        do {
            activeTrips = try await api.fetchTrips(status: "active")
        } catch {}
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        Text("\(greeting), \(auth.currentUser?.name ?? "Family")")
            .font(.title.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DesignTokens.Spacing.sectionTop)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                StatPill(
                    title: "Tasks",
                    value: "\(viewModel.summary?.tasks_today ?? 0)",
                    icon: "checkmark.circle.fill",
                    color: .blue
                )
                StatPill(
                    title: "Events",
                    value: "\(viewModel.summary?.appointments_today ?? 0)",
                    icon: "calendar.circle.fill",
                    color: .purple
                )
                StatPill(
                    title: "Grocery",
                    value: "\(viewModel.summary?.groceries_needed ?? 0)",
                    icon: "cart.circle.fill",
                    color: .green
                )
                if (viewModel.summary?.overdue_tasks ?? 0) > 0 {
                    StatPill(
                        title: "Overdue",
                        value: "\(viewModel.summary?.overdue_tasks ?? 0)",
                        icon: "exclamationmark.circle.fill",
                        color: .red
                    )
                }
            }
        }
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your tools")
                .font(.headline)

            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    FeatureTile(icon: "calendar", label: "Calendar", color: .purple) { showingCalendar = true }
                    FeatureTile(icon: "fork.knife", label: "Food", color: .green) { showingFood = true }
                    FeatureTile(icon: "refrigerator.fill", label: "Pantry", color: .cyan) { showingPantry = true }
                    FeatureTile(icon: "creditcard.fill", label: "Expenses", color: .orange) { showingExpenses = true }
                    FeatureTile(icon: "car.fill", label: "Trips", color: .blue) { showingTrips = true }
                    FeatureTile(icon: "flag.2.crossed.fill", label: "Rivalries", color: .red) { showingRivalries = true }
                    FeatureTile(icon: "bubble.left.and.bubble.right.fill", label: "Decisions", color: .indigo) { showingDecisions = true }
                    FeatureTile(icon: "gift.fill", label: "Gifts", color: .pink) { showingGifts = true }
                    FeatureTile(icon: "checkmark.circle", label: "Add Task", color: .blue) { showingAddTask = true }
                    FeatureTile(icon: "gearshape.fill", label: "Settings", color: .gray) { showingSettings = true }
                }
            }
        }
    }

    // MARK: - Live Activity

    @ViewBuilder
    private var liveActivitySection: some View {
        let hasContent = todaySteps != nil || !activeTrips.isEmpty
        if hasContent {
            VStack(alignment: .leading, spacing: 12) {
                Text("Right now")
                    .font(.headline)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        // Steps
                        if let steps = todaySteps {
                            HStack(spacing: 10) {
                                Image(systemName: "figure.walk")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(steps.formatted())")
                                        .font(.title3.bold())
                                        .monospacedDigit()
                                    Text("steps today")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignTokens.Spacing.cardGap)
                            .flCard(tint: .orange)
                        }

                        // Active trip
                        if let trip = activeTrips.first {
                            Button { showingTrips = true } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "car.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trip.traveler.capitalized)
                                            .font(.subheadline.bold())
                                        HStack(spacing: 4) {
                                            Text(trip.destination)
                                            if let eta = trip.eta_minutes {
                                                Text("· \(eta)m")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignTokens.Spacing.cardGap)
                                .flCard(tint: TabAccent.trips.color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Today Section

    @ViewBuilder
    private var todaySection: some View {
        if !viewModel.todayAppointments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.orange)
                    Text("Today")
                        .font(.headline)
                }
                ForEach(viewModel.todayAppointments) { appt in
                    AppointmentRow(appointment: appt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tasks Section

    @ViewBuilder
    private var tasksSection: some View {
        if !viewModel.activeTasks.isEmpty {
            let grouped = Dictionary(grouping: viewModel.activeTasks) { $0.category }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(.blue)
                    Text("Tasks")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.activeTasks.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                        .padding(.vertical, DesignTokens.Spacing.tinyLabel)
                        .glassEffect(.regular.tint(.blue.opacity(0.2)), in: .capsule)
                }
                ForEach(grouped.keys.sorted(), id: \.self) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(grouped[category] ?? []) { task in
                            TaskRow(task: task) {
                                Task { await viewModel.completeTask(task.id, api: api) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Grocery Section

    @ViewBuilder
    private var grocerySection: some View {
        if !viewModel.groceries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.green)
                    Text("Groceries")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingFood = true
                    } label: {
                        Text("All \(viewModel.groceries.count)")
                            .font(.caption.weight(.semibold))
                    }
                }
                ForEach(viewModel.groceries.prefix(4)) { grocery in
                    GroceryRow(grocery: grocery) {
                        Task { await viewModel.completeGrocery(grocery.id, api: api) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Feature Tile

struct FeatureTile: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) { tileContent }
            .buttonStyle(.plain)
    }

    private var tileContent: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .flCard(tint: color, interactive: true)
    }
}

// MARK: - Row Components

struct AppointmentRow: View {
    let appointment: AppointmentResponse

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.purple)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    if let time = appointment.appointment_time {
                        Label(time, systemImage: "clock")
                    }
                    if let location = appointment.location {
                        Label(location, systemImage: "mappin")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.calendar.color)
    }
}

struct TaskRow: View {
    let task: TaskResponse
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                if let assigned = task.assigned_to, !assigned.isEmpty {
                    Text(assigned.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if task.priority == "high" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: .blue)
    }
}

struct GroceryRow: View {
    let grocery: GroceryResponse
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            Text(grocery.item)
                .font(.subheadline)
            Spacer()
            if let category = grocery.category {
                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                    .padding(.vertical, DesignTokens.Spacing.tinyLabel)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: .green)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(APIService())
    .environment(AuthService())
}
