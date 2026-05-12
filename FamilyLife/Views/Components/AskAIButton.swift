import SwiftUI

/// Reusable AI suggestion button. Contextual to the feature it's placed in.
/// Usage: AskAIButton(context: .dinner) { suggestion in handleSuggestion(suggestion) }
struct AskAIButton: View {
    let context: AIContext
    var onSuggestion: ((String) -> Void)? = nil
    @State private var isSheetPresented = false
    @State private var hasConsent = AIConsentManager.hasConsented

    var body: some View {
        Button {
            if hasConsent {
                isSheetPresented = true
            } else {
                isSheetPresented = true // Will show disclosure first
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                Text("Ask AI")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(WarmPalette.cream1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [WarmPalette.peach, AccentTheme.terracotta.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
        }
        .sheet(isPresented: $isSheetPresented) {
            if hasConsent {
                AskAISheet(context: context, onSuggestion: onSuggestion)
            } else {
                AIDisclosureView(
                    onAccept: {
                        AIConsentManager.grant()
                        hasConsent = true
                        // Sheet will re-present with the actual AI sheet
                    },
                    onDecline: {
                        isSheetPresented = false
                    }
                )
            }
        }
    }
}

/// The context determines the AI prompt and placeholder text.
enum AIContext {
    case dinner
    case gifts(personName: String)
    case general

    var title: String {
        switch self {
        case .dinner: "Dinner ideas"
        case .gifts(let name): "Gift ideas for \(name)"
        case .general: "Ask AI"
        }
    }

    var placeholder: String {
        switch self {
        case .dinner: "Healthy, good for leftovers, no meat..."
        case .gifts(let name): "Thoughtful gift for \(name), under $50..."
        case .general: "What do you need help with?"
        }
    }

    var systemPrompt: String {
        switch self {
        case .dinner:
            "You are a helpful cooking assistant for a family. Suggest 2-3 recipe ideas based on the user's preferences. Keep responses concise with recipe name, cook time, and a brief description."
        case .gifts(let name):
            "You are a thoughtful gift advisor. Suggest 3-4 gift ideas for \(name) based on the user's description. Include price range and where to find each."
        case .general:
            "You are a helpful family assistant. Give concise, practical suggestions."
        }
    }
}

/// Sheet that accepts a text prompt and returns AI suggestions.
struct AskAISheet: View {
    let context: AIContext
    var onSuggestion: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(APIService.self) private var api
    @State private var query = ""
    @State private var result = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What are you looking for?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        HStack(spacing: 12) {
                            TextField(context.placeholder, text: $query, axis: .vertical)
                                .font(.system(size: 15))
                                .foregroundStyle(WarmPalette.ink1)
                                .lineLimit(3)
                            Button {
                                Task { await askAI() }
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(query.isEmpty ? WarmPalette.ink4 : AccentTheme.terracotta.color)
                            }
                            .disabled(query.isEmpty || isLoading)
                        }
                        .padding(14)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 40)
                            Spacer()
                        }
                    }

                    // Result
                    if !result.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AccentTheme.terracotta.color)
                                Text("AI SUGGESTION")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(WarmPalette.ink3)
                                    .tracking(0.4)
                            }
                            Text(result)
                                .font(.system(size: 15))
                                .foregroundStyle(WarmPalette.ink1)
                                .lineSpacing(4)

                            if let onSuggestion {
                                Button {
                                    onSuggestion(result)
                                    dismiss()
                                } label: {
                                    Text("Use this suggestion")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(WarmPalette.cream1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(WarmPalette.ink1)
                                        .clipShape(Capsule())
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(16)
                        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(22)
            }
            .background { AmbientBackground(style: .home) }
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
    }

    private func askAI() async {
        isLoading = true
        do {
            let recipes = try await api.suggestRecipes(query: query)
            if let first = recipes.first {
                result = "\(first.name) (\(first.cookTime) min, \(first.difficulty))\n\(first.steps.prefix(3).joined(separator: "\n"))"
            }
        } catch {
            result = "Couldn't get a suggestion right now. Try again."
        }
        isLoading = false
    }
}

#Preview {
    AskAIButton(context: .dinner)
        .environment(APIService())
}
