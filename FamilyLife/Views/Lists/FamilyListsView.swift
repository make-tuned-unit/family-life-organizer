import SwiftUI

// MARK: - Family Lists — each list is its own entity with its own items

struct FamilyListsView: View {
    @Binding var pendingListName: String?
    @Environment(APIService.self) private var api
    @State private var lists: [APIService.ListResponse] = []
    @State private var selectedList: APIService.ListResponse?
    @State private var showingNewList = false
    @State private var isLoading = false
    // "Tasks" is a reserved, synthetic entry backed by the tasks table (not list_items).
    #if DEBUG
    @State private var tasksSelected = ProcessInfo.processInfo.environment["UITEST_LIST"] == "tasks"
    #else
    @State private var tasksSelected = false
    #endif
    @State private var activeTaskCount = 0

    private static let tasksReservedName = "Tasks"

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            // List chips — tap navigates to that list
            listPicker

            // Selected list content
            if tasksSelected {
                TasksDetailSection(api: api) { count in activeTaskCount = count }
            } else if let selected = selectedList {
                ListDetailSection(list: selected, api: api)
            } else if lists.isEmpty && !isLoading {
                WarmEmptyState(
                    title: "No lists yet",
                    systemImage: "list.bullet.rectangle",
                    description: "Create your first list to get started"
                )
                .padding(.top, 40)
            }

            Spacer()
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(systemName: "plus", accessibilityLabel: "Add list") {
                    showingNewList = true
                }
            }
        }
        .sheet(isPresented: $showingNewList) {
            NewListSheet { await loadLists() }
        }
        .overlay {
            if isLoading && lists.isEmpty { ProgressView() }
        }
        .refreshable { await loadLists() }
        .task { await loadLists() }
        .onChange(of: pendingListName) {
            if let name = pendingListName {
                Task { await navigateToList(named: name) }
            }
        }
    }

    private func navigateToList(named name: String) async {
        // "Tasks" is reserved for the real tasks store — never create a list_items stub for it.
        if name.localizedCaseInsensitiveCompare(Self.tasksReservedName) == .orderedSame {
            tasksSelected = true
            selectedList = nil
            pendingListName = nil
            return
        }
        if let match = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            tasksSelected = false
            selectedList = match
        } else if let result = try? await api.createList(["name": name, "icon": "list.bullet"]) {
            await loadLists()
            tasksSelected = false
            selectedList = lists.first { $0.id == result.id }
        }
        pendingListName = nil
    }

    private func loadLists() async {
        isLoading = true
        do {
            // Hide any legacy empty "Tasks" list_items stub — the synthetic Tasks chip replaces it.
            lists = try await api.fetchLists()
                .filter { $0.name.localizedCaseInsensitiveCompare(Self.tasksReservedName) != .orderedSame }
            activeTaskCount = (try? await api.fetchTasks(status: "active").count) ?? activeTaskCount
            // Deep-link takes priority
            if let name = pendingListName {
                await navigateToList(named: name)
            } else if !tasksSelected, selectedList == nil, let first = lists.first {
                selectedList = first
            }
            // Update selected list data if it still exists
            if let sel = selectedList {
                selectedList = lists.first { $0.id == sel.id } ?? lists.first
            }
        } catch {
            guard !error.isCancellation else { return }
        }
        isLoading = false
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(lists.count) LISTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink3)
                    .tracking(0.4)
                Text("Lists")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WarmPalette.ink1)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - List Picker

    private var listPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Synthetic, always-first Tasks chip (real to-dos, not list_items)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tasksSelected = true
                        selectedList = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Tasks")
                            .font(.system(size: 13, weight: .semibold))
                        if activeTaskCount > 0 {
                            Text("\(activeTaskCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tasksSelected ? WarmPalette.cream1.opacity(0.7) : WarmPalette.ink3)
                        }
                    }
                    .foregroundStyle(tasksSelected ? WarmPalette.cream1 : WarmPalette.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tasksSelected ? WarmPalette.ink1 : .clear)
                    .clipShape(Capsule())
                    .background(WarmPalette.cardSurface, in: Capsule())
                }
                .buttonStyle(.plain)

                ForEach(lists) { list in
                    let isActive = !tasksSelected && selectedList?.id == list.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tasksSelected = false
                            selectedList = list
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: list.isPinned ? "pin.fill" : (list.icon ?? "list.bullet"))
                                .font(.system(size: 12))
                            Text(list.name)
                                .font(.system(size: 13, weight: .semibold))
                            if let count = list.active_count, count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(isActive ? WarmPalette.cream1.opacity(0.7) : WarmPalette.ink3)
                            }
                        }
                        .foregroundStyle(isActive ? WarmPalette.cream1 : WarmPalette.ink2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isActive ? WarmPalette.ink1 : .clear)
                        .clipShape(Capsule())
                        .background(WarmPalette.cardSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task {
                                if list.isPinned {
                                    try? await api.unpinList(id: list.id)
                                } else {
                                    try? await api.pinList(id: list.id)
                                }
                                await loadLists()
                            }
                        } label: {
                            Label(
                                list.isPinned ? "Remove from Home" : "Show on Home",
                                systemImage: list.isPinned ? "pin.slash" : "pin.fill"
                            )
                        }
                        Button(role: .destructive) {
                            Task {
                                try? await api.deleteList(id: list.id)
                                await loadLists()
                            }
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    }
                }

                // Quick add list button
                Button { showingNewList = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11))
                        Text("New").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(WarmPalette.ink3)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(WarmPalette.ink1.opacity(0.08)))
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - List Detail Section (items for selected list)

struct ListDetailSection: View {
    let list: APIService.ListResponse
    let api: APIService
    @State private var items: [APIService.ListItemResponse] = []
    @State private var newItem = ""
    @State private var isLoading = false
    @State private var showCompleted = false
    @State private var editingItemId: Int?
    @State private var editingText = ""
    @State private var recentlyToggledIds: Set<Int> = []
    @FocusState private var isInputFocused: Bool
    @FocusState private var isEditFocused: Bool

    // Items currently being animated (checked off but still shown in active section)
    private var activeItems: [APIService.ListItemResponse] {
        items.filter { !$0.isDone || recentlyToggledIds.contains($0.id) }
    }

    private var doneItems: [APIService.ListItemResponse] {
        items.filter { $0.isDone && !recentlyToggledIds.contains($0.id) }
    }

    // Group active items by category for grocery lists
    private var categorizedActiveItems: [(category: String, items: [APIService.ListItemResponse])] {
        let grouped = Dictionary(grouping: activeItems) { $0.category ?? "Other" }
        let order = ["Produce", "Dairy", "Meat & Seafood", "Bakery", "Deli", "Frozen", "Pantry", "Beverages", "Snacks", "Household", "Personal Care", "Baby & Kids", "Pet", "Other"]
        return order.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items)
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Produce": return "leaf.fill"
        case "Dairy": return "cup.and.saucer.fill"
        case "Meat & Seafood": return "fish.fill"
        case "Bakery": return "birthday.cake.fill"
        case "Deli": return "takeoutbag.and.cup.and.straw.fill"
        case "Frozen": return "snowflake"
        case "Pantry": return "cabinet.fill"
        case "Beverages": return "waterbottle.fill"
        case "Snacks": return "popcorn.fill"
        case "Household": return "house.fill"
        case "Personal Care": return "heart.fill"
        case "Baby & Kids": return "figure.and.child.holdinghands"
        case "Pet": return "pawprint.fill"
        default: return "bag.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Quick add bar
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(WarmPalette.ink3)
                    TextField("Add item...", text: $newItem)
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink1)
                        .focused($isInputFocused)
                        .onSubmit { addItem() }
                }
                .padding(12)
                .background(WarmPalette.cardSurface, in: Capsule())

                if !newItem.isEmpty {
                    Button { addItem() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(TabAccent.home.color)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            if list.isGrocery {
                groceryContent
            } else {
                flatListContent
            }
        }
        .task(id: list.id) { await loadItems() }
    }

    // MARK: - Flat List with Drag Reorder

    private var flatListContent: some View {
        List {
            if activeItems.isEmpty && doneItems.isEmpty && !isLoading {
                WarmEmptyState(
                    title: "List is empty",
                    systemImage: list.icon ?? "list.bullet",
                    description: "Add items above to get started"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !activeItems.isEmpty {
                Section {
                    ForEach(activeItems) { item in
                        itemRowContent(item)
                            .listRowBackground(WarmPalette.cardSurface)
                    }
                    .onMove(perform: moveItems)
                }
            }

            if !doneItems.isEmpty {
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showCompleted.toggle() }
                    } label: {
                        HStack {
                            Text("Completed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink3)
                            Text("\(doneItems.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WarmPalette.ink4)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink4)
                                .rotationEffect(.degrees(showCompleted ? 90 : 0))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if showCompleted {
                        ForEach(doneItems) { item in
                            itemRowContent(item)
                                .listRowBackground(WarmPalette.cardSurface.opacity(0.6))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Grocery Grouped (ScrollView, no reorder)

    private var groceryContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if activeItems.isEmpty && doneItems.isEmpty && !isLoading {
                    WarmEmptyState(
                        title: "List is empty",
                        systemImage: list.icon ?? "list.bullet",
                        description: "Add items above to get started"
                    )
                }

                ForEach(categorizedActiveItems, id: \.category) { group in
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(group.category))
                                .font(.system(size: 12))
                                .foregroundStyle(TabAccent.home.color)
                            Text(group.category)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WarmPalette.ink2)
                            Text("\(group.items.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink4)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GlassDivider() }
                                groceryItemRow(item)
                            }
                        }
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 8)
                    }
                }

                // Completed section
                if !doneItems.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showCompleted.toggle() }
                    } label: {
                        HStack {
                            Text("Completed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink3)
                            Text("\(doneItems.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WarmPalette.ink4)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WarmPalette.ink4)
                                .rotationEffect(.degrees(showCompleted ? 90 : 0))
                        }
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 6)
                    }
                    .buttonStyle(.plain)

                    if showCompleted {
                        VStack(spacing: 0) {
                            ForEach(Array(doneItems.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GlassDivider() }
                                groceryItemRow(item)
                            }
                        }
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 14)
                        .opacity(0.6)
                    }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
    }

    // MARK: - Item Row (used in List for flat lists)

    @ViewBuilder
    private func itemRowContent(_ item: APIService.ListItemResponse) -> some View {
        let isEditing = editingItemId == item.id
        HStack(spacing: 12) {
            Button {
                Task { await toggleItem(item.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? WarmPalette.good : WarmPalette.ink4)
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("Item name", text: $editingText)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .focused($isEditFocused)
                    .onSubmit { commitEdit(item) }
            } else {
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? WarmPalette.ink3 : WarmPalette.ink1)
                    .strikethrough(item.isDone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !item.isDone else { return }
                        editingItemId = item.id
                        editingText = item.title
                        isEditFocused = true
                    }
            }

            if isEditing {
                Button { commitEdit(item) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WarmPalette.good)
                }
                .buttonStyle(.plain)
                Button { editingItemId = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WarmPalette.ink4)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            if !item.isDone {
                Button {
                    editingItemId = item.id
                    editingText = item.title
                    isEditFocused = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                Task { await deleteItem(item.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Grocery Item Row (used in ScrollView for grocery lists)

    @ViewBuilder
    private func groceryItemRow(_ item: APIService.ListItemResponse) -> some View {
        let isEditing = editingItemId == item.id
        HStack(spacing: 12) {
            Button {
                Task { await toggleItem(item.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? WarmPalette.good : WarmPalette.ink4)
            }

            if isEditing {
                TextField("Item name", text: $editingText)
                    .font(.system(size: 15))
                    .foregroundStyle(WarmPalette.ink1)
                    .focused($isEditFocused)
                    .onSubmit { commitEdit(item) }
            } else {
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? WarmPalette.ink3 : WarmPalette.ink1)
                    .strikethrough(item.isDone)
                    .onTapGesture {
                        guard !item.isDone else { return }
                        editingItemId = item.id
                        editingText = item.title
                        isEditFocused = true
                    }
            }

            Spacer()

            if isEditing {
                Button { commitEdit(item) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WarmPalette.good)
                }
                Button { editingItemId = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WarmPalette.ink4)
                }
            } else if let by = item.added_by, !by.isEmpty, !item.isDone {
                Text(by)
                    .font(.system(size: 11))
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .contextMenu {
            if !item.isDone {
                Button {
                    editingItemId = item.id
                    editingText = item.title
                    isEditFocused = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                Task { await deleteItem(item.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func loadItems() async {
        isLoading = true
        do {
            items = try await api.fetchListItems(listId: list.id)
        } catch {
            guard !error.isCancellation else { return }
        }
        isLoading = false
    }

    private func addItem() {
        let title = newItem.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newItem = ""
        isInputFocused = true
        Task {
            do {
                let _ = try await api.addListItem(listId: list.id, title: title)
                await loadItems()
            } catch {
                guard !error.isCancellation else { return }
            }
        }
    }

    private func toggleItem(_ id: Int) async {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let wasDone = items[idx].isDone

        // Keep item in its current section during animation
        if !wasDone {
            recentlyToggledIds.insert(id)
        }

        // Flip the is_done flag so checkmark + strikethrough appear
        withAnimation(.easeInOut(duration: 0.2)) {
            items[idx].is_done = wasDone ? 0 : 1
        }

        // Pause so user sees the visual feedback before item moves
        if !wasDone {
            try? await Task.sleep(for: .milliseconds(700))
        }

        // Release from hold — item moves to correct section
        recentlyToggledIds.remove(id)

        do {
            try await api.toggleListItem(id: id)
            await loadItems()
        } catch {
            guard !error.isCancellation else { return }
            await loadItems()
        }
    }

    private func deleteItem(_ id: Int) async {
        do {
            try await api.deleteListItem(id: id)
            items.removeAll { $0.id == id }
        } catch {
            guard !error.isCancellation else { return }
        }
    }

    private func commitEdit(_ item: APIService.ListItemResponse) {
        let trimmed = editingText.trimmingCharacters(in: .whitespaces)
        editingItemId = nil
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        Task {
            do {
                try await api.updateListItem(id: item.id, title: trimmed)
                await loadItems()
            } catch {
                guard !error.isCancellation else { return }
            }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var active = activeItems
        active.move(fromOffsets: source, toOffset: destination)
        // Update local state immediately
        items = active + doneItems
        // Persist to server
        let orderedIds = active.map(\.id)
        Task {
            try? await api.reorderListItems(listId: list.id, orderedIds: orderedIds)
        }
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    let onComplete: () async -> Void
    @Environment(APIService.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "list.bullet"
    @State private var isGroceryList = false

    private let icons = [
        ("list.bullet", "General"),
        ("cart.fill", "Grocery"),
        ("checkmark.circle.fill", "Chores"),
        ("suitcase.fill", "Packing"),
        ("gift.fill", "Gifts"),
        ("wrench.fill", "Projects"),
        ("book.fill", "Reading"),
        ("film.fill", "Movies"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("List Name") {
                    TextField("e.g. Grocery, Camping Trip, Spring Cleaning", text: $name)
                }

                Section {
                    Toggle(isOn: $isGroceryList) {
                        HStack(spacing: 10) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(TabAccent.home.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Grocery List")
                                    .font(.system(size: 15, weight: .medium))
                                Text("Auto-sort items into categories like Produce, Dairy, Meat")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WarmPalette.ink3)
                            }
                        }
                    }
                    .tint(TabAccent.home.color)
                    .onChange(of: isGroceryList) {
                        if isGroceryList { selectedIcon = "cart.fill" }
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(icons, id: \.0) { icon, label in
                            Button {
                                selectedIcon = icon
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .frame(width: 44, height: 44)
                                        .background(selectedIcon == icon ? TabAccent.home.color.opacity(0.15) : WarmPalette.ink1.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedIcon == icon ? TabAccent.home.color : .clear, lineWidth: 2)
                                        )
                                    Text(label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(WarmPalette.ink3)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedIcon == icon ? TabAccent.home.color : WarmPalette.ink2)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(style: .home) }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            var body: [String: Any] = ["name": name, "icon": selectedIcon]
                            if isGroceryList {
                                body["list_type"] = "grocery"
                            }
                            let _ = try? await api.createList(body)
                            await onComplete()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Tasks Detail Section (real to-dos from the tasks table, grouped by category)

struct TasksDetailSection: View {
    let api: APIService
    var onCountChange: (Int) -> Void = { _ in }

    @State private var tasks: [TaskResponse] = []
    @State private var newTask = ""
    @State private var isLoading = false
    @State private var showCompleted = false
    @State private var recentlyToggledIds: Set<Int> = []
    @FocusState private var isInputFocused: Bool

    private var activeTasks: [TaskResponse] {
        tasks.filter { $0.status == "active" || recentlyToggledIds.contains($0.id) }
    }

    private var doneTasks: [TaskResponse] {
        tasks.filter { $0.status != "active" && !recentlyToggledIds.contains($0.id) }
    }

    /// Active tasks grouped by category, with "general" rendered as "To-Do" and sorted last.
    private var groupedActive: [(category: String, items: [TaskResponse])] {
        let grouped = Dictionary(grouping: activeTasks) { displayCategory($0.category) }
        return grouped
            .map { (category: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                if lhs.category == "To-Do" { return false }
                if rhs.category == "To-Do" { return true }
                return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
            }
    }

    private func displayCategory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.lowercased() == "general" { return "To-Do" }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Quick add bar
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(WarmPalette.ink3)
                    TextField("Add a task...", text: $newTask)
                        .font(.system(size: 15))
                        .foregroundStyle(WarmPalette.ink1)
                        .focused($isInputFocused)
                        .onSubmit { addTask() }
                }
                .padding(12)
                .background(WarmPalette.cardSurface, in: Capsule())

                if !newTask.isEmpty {
                    Button { addTask() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(TabAccent.home.color)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if activeTasks.isEmpty && doneTasks.isEmpty && !isLoading {
                        WarmEmptyState(
                            title: "No tasks yet",
                            systemImage: "checkmark.circle",
                            description: "Add one above, or ask the concierge to."
                        )
                        .padding(.top, 40)
                    }

                    ForEach(groupedActive, id: \.category) { group in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(group.category)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WarmPalette.ink2)
                                Text("\(group.items.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink4)
                                Spacer()
                            }
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, task in
                                    if index > 0 { GlassDivider() }
                                    taskRow(task)
                                }
                            }
                            .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.bottom, 8)
                        }
                    }

                    if !doneTasks.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showCompleted.toggle() }
                        } label: {
                            HStack {
                                Text("Completed")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink3)
                                Text("\(doneTasks.count)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WarmPalette.ink4)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink4)
                                    .rotationEffect(.degrees(showCompleted ? 90 : 0))
                            }
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                            .padding(.vertical, 10)
                        }

                        if showCompleted {
                            VStack(spacing: 0) {
                                ForEach(Array(doneTasks.enumerated()), id: \.element.id) { index, task in
                                    if index > 0 { GlassDivider() }
                                    taskRow(task)
                                }
                            }
                            .background(WarmPalette.cardSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        }
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
        }
        .task { await loadTasks() }
    }

    private func taskRow(_ task: TaskResponse) -> some View {
        let isDone = task.status != "active" || recentlyToggledIds.contains(task.id)
        return HStack(spacing: 12) {
            Button { toggleComplete(task) } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isDone ? WarmPalette.good : WarmPalette.ink4)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? WarmPalette.ink4 : WarmPalette.ink1)
                    .strikethrough(isDone, color: WarmPalette.ink4)
                if let due = dueLabel(task) {
                    Text(due.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(due.overdue ? WarmPalette.bad : WarmPalette.ink3)
                }
            }
            Spacer()
            if task.priority == "high" && !isDone {
                Circle().fill(WarmPalette.bad).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func dueLabel(_ task: TaskResponse) -> (text: String, overdue: Bool)? {
        guard let raw = task.due_date, !raw.isEmpty,
              let date = DateFormatter.isoDate.date(from: raw) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        if day < today { return ("Overdue · \(fmt.string(from: date))", true) }
        if cal.isDateInToday(date) { return ("Due today", false) }
        if cal.isDateInTomorrow(date) { return ("Due tomorrow", false) }
        return ("Due \(fmt.string(from: date))", false)
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTask = ""
        Task {
            try? await api.addTask(["title": title, "category": "general", "priority": "medium"])
            await loadTasks()
        }
    }

    private func toggleComplete(_ task: TaskResponse) {
        guard task.status == "active" else { return }
        // Show checkmark + strikethrough in place, then let it fade out of the active list.
        withAnimation(.easeInOut(duration: 0.2)) { _ = recentlyToggledIds.insert(task.id) }
        Task {
            try? await api.completeTask(id: task.id)
            try? await Task.sleep(for: .milliseconds(700))
            await loadTasks()
            withAnimation(.easeInOut(duration: 0.2)) { _ = recentlyToggledIds.remove(task.id) }
        }
    }

    private func loadTasks() async {
        isLoading = true
        do {
            async let active = api.fetchTasks(status: "active")
            async let done = api.fetchTasks(status: "completed")
            let (a, d) = try await (active, done)
            tasks = a + d
            onCountChange(a.count)
        } catch {
            guard !error.isCancellation else { return }
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        FamilyListsView(pendingListName: .constant(nil))
    }
    .environment(APIService())
}
