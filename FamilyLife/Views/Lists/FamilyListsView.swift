import SwiftUI

// MARK: - Family Lists — each list is its own entity with its own items

struct FamilyListsView: View {
    @Environment(APIService.self) private var api
    @State private var lists: [APIService.ListResponse] = []
    @State private var selectedList: APIService.ListResponse?
    @State private var showingNewList = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            // List chips — tap navigates to that list
            listPicker

            // Selected list content
            if let selected = selectedList {
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
                GlassIconButton(systemName: "plus") {
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
    }

    private func loadLists() async {
        isLoading = true
        do {
            lists = try await api.fetchLists()
            // Auto-select first list if none selected
            if selectedList == nil, let first = lists.first {
                selectedList = first
            }
            // Update selected list data if it still exists
            if let sel = selectedList {
                selectedList = lists.first { $0.id == sel.id } ?? lists.first
            }
        } catch {}
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
                ForEach(lists) { list in
                    let isActive = selectedList?.id == list.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedList = list }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: list.icon ?? "list.bullet")
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
                        .glassEffect(.regular.tint(isActive ? .clear : .white.opacity(0.05)), in: .capsule)
                    }
                    .buttonStyle(.plain)
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
    @State private var showingDeleteConfirm = false

    private var activeItems: [APIService.ListItemResponse] {
        items.filter { !$0.isDone }
    }

    private var doneItems: [APIService.ListItemResponse] {
        items.filter { $0.isDone }
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
                        .onSubmit { addItem() }
                }
                .padding(12)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .capsule)

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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if activeItems.isEmpty && doneItems.isEmpty && !isLoading {
                        WarmEmptyState(
                            title: "List is empty",
                            systemImage: list.icon ?? "list.bullet",
                            description: "Add items above to get started"
                        )
                    }

                    // Active items
                    if !activeItems.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GlassDivider() }
                                ListItemRow(item: item) {
                                    Task { await toggleItem(item.id) }
                                } onDelete: {
                                    Task { await deleteItem(item.id) }
                                }
                            }
                        }
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 14)
                    }

                    // Completed items
                    if !doneItems.isEmpty {
                        WarmSectionHeader(title: "Completed", trailing: "\(doneItems.count)")
                            .padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(Array(doneItems.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GlassDivider() }
                                ListItemRow(item: item) {
                                    Task { await toggleItem(item.id) }
                                } onDelete: {
                                    Task { await deleteItem(item.id) }
                                }
                            }
                        }
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                        .padding(.bottom, 14)
                        .opacity(0.6)
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
            }
        }
        .task(id: list.id) { await loadItems() }
    }

    private func loadItems() async {
        isLoading = true
        do { items = try await api.fetchListItems(listId: list.id) } catch {}
        isLoading = false
    }

    private func addItem() {
        let title = newItem.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newItem = ""
        Task {
            do {
                let _ = try await api.addListItem(listId: list.id, title: title)
                await loadItems()
            } catch {}
        }
    }

    private func toggleItem(_ id: Int) async {
        do {
            try await api.toggleListItem(id: id)
            await loadItems()
        } catch {}
    }

    private func deleteItem(_ id: Int) async {
        do {
            try await api.deleteListItem(id: id)
            items.removeAll { $0.id == id }
        } catch {}
    }
}

// MARK: - List Item Row

struct ListItemRow: View {
    let item: APIService.ListItemResponse
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? WarmPalette.good : WarmPalette.ink4)
            }
            Text(item.title)
                .font(.system(size: 15))
                .foregroundStyle(item.isDone ? WarmPalette.ink3 : WarmPalette.ink1)
                .strikethrough(item.isDone)
            Spacer()
            if let by = item.added_by, !by.isEmpty {
                Text(by)
                    .font(.system(size: 11))
                    .foregroundStyle(WarmPalette.ink4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
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
                            let _ = try? await api.createList(["name": name, "icon": selectedIcon])
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

#Preview {
    NavigationStack {
        FamilyListsView()
    }
    .environment(APIService())
}
