import SwiftUI

/// Developer API keys: lets a paid household plug its own agent (Claude, ChatGPT,
/// a custom bot) into Kinrows. Keys drive the same tool surface the Concierge
/// uses. The plaintext is shown exactly once, right after creation.
struct DeveloperAPIView: View {
    @Environment(APIService.self) private var api

    @State private var keys: [APIService.DeveloperKey] = []
    @State private var loading = true
    @State private var error: String?
    @State private var needsPremium = false

    // Create flow
    @State private var newName = ""
    @State private var newScope = "write"
    @State private var isWorking = false
    @State private var freshKey: APIService.DeveloperKeyCreated?
    @State private var copied = false

    private static let docsURL = URL(string: "https://kinrows.com/developers.html")!

    var body: some View {
        Form {
            if needsPremium {
                Section {
                    WarmEmptyState(
                        title: "Bring your own agent",
                        systemImage: "terminal.fill",
                        description: "With Concierge, you can mint an API key and let your own AI agent run Kinrows for you — add tasks, update lists, log expenses, and more."
                    )
                }
            } else {
                if let freshKey {
                    Section {
                        Text(freshKey.key)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = freshKey.key
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy key", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        Button("Done") { self.freshKey = nil; copied = false }
                    } header: {
                        Text("Your new key")
                    } footer: {
                        Text("This is the only time the full key is shown. Store it somewhere safe — anyone with it can act as you in Kinrows.")
                    }
                }

                Section {
                    if loading {
                        FLLoadingState(message: "Loading…")
                    } else if keys.isEmpty {
                        Text("No active keys yet.")
                            .font(.flSubheadline).foregroundStyle(WarmPalette.ink3)
                    } else {
                        ForEach(keys) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(key.name).font(.flHeadline)
                                    Spacer()
                                    Text(key.scope == "read" ? "Read-only" : "Read & write")
                                        .font(.flCaption)
                                        .foregroundStyle(key.scope == "read" ? AccentTheme.sage.color : WarmPalette.ink2)
                                }
                                Text("\(key.key_prefix)…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(WarmPalette.ink3)
                                Text(lastUsedLabel(key.last_used_at))
                                    .font(.flCaption2).foregroundStyle(WarmPalette.ink3)
                            }
                            .swipeActions {
                                Button(role: .destructive) { revoke(key) } label: { Label("Revoke", systemImage: "trash") }
                            }
                        }
                    }
                } header: {
                    Text("Active keys")
                } footer: {
                    Text("Swipe a key to revoke it. Revoked keys stop working immediately.")
                }

                Section("Create a key") {
                    TextField("Name (e.g. My Claude agent)", text: $newName)
                    Picker("Access", selection: $newScope) {
                        Text("Read & write").tag("write")
                        Text("Read-only").tag("read")
                    }
                    Button("Create key") { create() }
                        .disabled(isWorking)
                }

                Section {
                    Link(destination: Self.docsURL) {
                        Label("Read the developer docs", systemImage: "book")
                    }
                } footer: {
                    Text("Works with any agent that can call HTTP tools, and as an MCP server for Claude, ChatGPT and Cursor.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(style: .settings) }
        .navigationTitle("Developer API")
        .navigationBarTitleDisplayMode(.inline)
        .inlineError(error) { error = nil }
        .task { await load() }
    }

    private func lastUsedLabel(_ raw: String?) -> String {
        guard let raw, let date = ISO8601DateFormatter.flexible.date(from: raw) else { return "Never used" }
        return "Last used \(date.formatted(.relative(presentation: .named)))"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            keys = try await api.fetchDeveloperKeys()
            needsPremium = false
        } catch APIError.serverMessage(402, _), APIError.serverError(402) {
            needsPremium = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let created = try await api.createDeveloperKey(
                    name: newName.trimmingCharacters(in: .whitespaces).isEmpty ? "My agent" : newName,
                    scope: newScope)
                freshKey = created
                newName = ""
                copied = false
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func revoke(_ key: APIService.DeveloperKey) {
        Task {
            do {
                try await api.revokeDeveloperKey(id: key.id)
                keys.removeAll { $0.id == key.id }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { DeveloperAPIView() }
        .environment(APIService())
}
