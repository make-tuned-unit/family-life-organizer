import Foundation

@Observable
final class ConciergeViewModel {
    enum LoadState {
        case idle, loading, loaded(ConciergeBrief), failed(String)
    }

    private(set) var state: LoadState = .idle
    /// When set, an on-device-generated summary to show in place of the server one.
    private(set) var onDeviceSummary: String?

    var brief: ConciergeBrief? {
        if case let .loaded(brief) = state { return brief }
        return nil
    }

    func load(api: APIService, force: Bool = false) async {
        if case .loaded = state {} else { state = .loading }

        // Cloud AI defaults ON. When the brief can be summarized on-device, or the
        // user turned cloud AI off, ask the server to skip the Anthropic call so no
        // household data is sent for the brief.
        let cloudAIEnabled = (UserDefaults.standard.object(forKey: "cloudAIEnabled") as? Bool) ?? true
        let canSummarizeOnDevice = OnDeviceSummarizer.isAvailable
        let uitest = ProcessInfo.processInfo.environment["UITEST_AUTOLOGIN"] != nil
        // Screenshot harness wants the server's clean bullet formatting → don't skip.
        let skipCloud = !uitest && (canSummarizeOnDevice || !cloudAIEnabled)

        do {
            let brief = try await api.fetchConciergeBrief(forceRefresh: force, skipAI: skipCloud)
            onDeviceSummary = nil
            state = .loaded(brief)
            // Regenerate the prose privately on-device when available (cards already shown).
            if !uitest, canSummarizeOnDevice {
                onDeviceSummary = await OnDeviceSummarizer.summarize(brief)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
