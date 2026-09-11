// Compile with the production view model; API is an isolated event fixture.
// xcrun swiftc FamilyLife/Views/Concierge/ConciergeChatViewModel.swift test/concierge-streaming.swift -o /tmp/concierge-stream-check
// /tmp/concierge-stream-check
import Foundation
struct ConciergeAction: Equatable { var summary: String }
enum ConciergeMessageSource { case text }
struct Reply { var conversationId: Int; var reply: String; var actions: [ConciergeAction] = [] }
enum Event { case delta(String), action(ConciergeAction), done(Reply) }
struct History { var role: String; var content: String }
@MainActor final class APIService {
    var events: [Event] = []
    var fails = false
    static var writes = 0
    static func publishConciergeActions(_ actions: [ConciergeAction]) { writes += actions.count }
    func fetchConciergeMessages(conversationId: Int) async throws -> [History] { [] }
    func conciergeMessageStream(_ text: String, conversationId: Int?, source: ConciergeMessageSource) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if fails { continuation.finish(throwing: NSError(domain: "Interrupted", code: 1)) }
            else { continuation.finish() }
        }
    }
}
@main struct Checks {
    @MainActor static func main() async {
        let api = APIService()
        let vm = ConciergeChatViewModel()
        let answer = "Your week is ready.\n\n- **Violin:** Rowan, weekly at 9:20 AM.\n- **Location:** Your saved music school.\n\nEverything is saved."
        api.events = [.delta("Checking…"), .action(.init(summary: "Saved violin")), .done(.init(conversationId: 7, reply: answer, actions: [.init(summary: "Saved violin")]))]
        let send = Task { await vm.send("Plan my week", api: api) }
        try! await Task.sleep(for: .milliseconds(100))
        assert(vm.isSending)
        assert(vm.messages.last!.text.count < answer.count)
        vm.startNew()
        assert(vm.messages.count == 2, "New thread must not corrupt an active reply")
        await send.value
        assert(vm.messages.last!.text == answer)
        assert(vm.conversationId == 7 && !vm.isSending)
        assert(APIService.writes == 1)
        vm.startNew()
        api.events = [.delta("A partial answer")]; api.fails = true
        await vm.send("Hello", api: api)
        assert(vm.messages.last!.text == "A partial answer")
        assert(vm.errorMessage != nil && !vm.isSending)
        vm.startNew(); api.fails = false
        api.events = [.done(.init(conversationId: 8, reply: answer))]
        await vm.send("Hello", api: api, reduceMotion: true)
        assert(vm.messages.last!.text == answer)
        print("PASS: paced reveal, authoritative reconciliation, thread guard, action deduplication, interrupted reply, Reduce Motion")
    }
}
