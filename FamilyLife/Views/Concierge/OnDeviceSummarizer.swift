import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates the concierge brief's prose summary on-device via Apple's
/// FoundationModels (iOS 26+) — private, offline, zero token cost. Returns nil
/// whenever the model is unavailable so callers fall back to the server summary.
enum OnDeviceSummarizer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func summarize(_ brief: ConciergeBrief) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let instructions = """
            You are a warm family life concierge. In 2-3 short sentences, summarize what \
            needs attention today in priority order. Calm and reassuring. No lists, no markdown, \
            no preamble. If nothing needs attention, say so warmly.
            """
            let prompt: String
            if brief.cards.isEmpty {
                prompt = "Nothing needs attention today."
            } else {
                let items = brief.cards.prefix(8).map { "- \($0.title): \($0.subtitle)" }.joined(separator: "\n")
                prompt = "Today's items:\n\(items)"
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
