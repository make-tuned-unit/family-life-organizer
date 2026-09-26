// Compiled against the production policy by test/concierge-launcher.test.js:
// xcrun swiftc FamilyLife/Views/Concierge/ConciergeLauncherPress.swift test/concierge-launcher-press.swift -o <out>
import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}

@main struct Checks {
    static func main() {
        // Tap (released before the hold timer) opens the Concierge tab.
        for consent in [true, false] {
            var p = ConciergeLauncherPress()
            let token = p.pressBegan(hasConsent: consent)
            check(token != nil, "press begins")
            check(p.pressEnded() == .open, "tap opens (consent=\(consent))")
            check(p.holdElapsed(pressID: token!) == nil, "late hold timer after a tap is ignored")
        }

        // Hold with consent → in-place push-to-talk, release sends.
        var granted = ConciergeLauncherPress()
        let g = granted.pressBegan(hasConsent: true)!
        check(granted.pressBegan(hasConsent: true) == nil, "drag updates don't restart the press")
        check(granted.holdElapsed(pressID: g) == .beginPushToTalk, "consented hold starts listening")
        check(granted.holdElapsed(pressID: g) == nil, "hold fires once")
        check(granted.pressEnded() == .endPushToTalk, "consented release sends")

        // REGRESSION: hold without consent must still be a hold — routed to the
        // listen flow (disclosure → chat listening), never swallowed or a tap.
        var fresh = ConciergeLauncherPress()
        let f = fresh.pressBegan(hasConsent: false)
        check(f != nil, "unconsented press is tracked, not dropped")
        check(fresh.holdElapsed(pressID: f!) == .awaitRelease, "unconsented hold is recognised")
        check(fresh.pressEnded() == .listenAfterConsent, "unconsented hold routes to listening")

        // A stale timer from an earlier press can't promote the next press.
        var stale = ConciergeLauncherPress()
        let first = stale.pressBegan(hasConsent: true)!
        _ = stale.pressEnded()
        _ = stale.pressBegan(hasConsent: true)
        check(stale.holdElapsed(pressID: first) == nil, "stale hold timer ignored")
        check(stale.pressEnded() == .open, "second quick press is a tap")

        check(ConciergeLauncherPress.holdThreshold <= .milliseconds(500), "hold threshold stays snappy")
        print("ok")
    }
}
