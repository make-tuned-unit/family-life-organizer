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
        do {
            let brief = try await api.fetchConciergeBrief(forceRefresh: force)
            onDeviceSummary = nil
            state = .loaded(brief)
            // Privately re-summarize on-device when available (non-blocking for cards).
            if OnDeviceSummarizer.isAvailable {
                onDeviceSummary = await OnDeviceSummarizer.summarize(brief)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
