import Foundation

/// Pure decision logic for the floating ✨ Concierge launcher's press gesture,
/// kept free of SwiftUI so `test/concierge-launcher-press.swift` can pin it.
///
/// Contract (regression guard — a consent-gated `onChanged` once swallowed every
/// hold silently, so touch-and-hold appeared to do nothing):
/// - Tap → open the Concierge tab.
/// - Hold with Concierge consent → live push-to-talk in place; release sends.
/// - Hold WITHOUT consent → still recognised as a hold; release routes to the
///   Concierge listen flow (AI disclosure first, then the chat opens listening).
///   A hold must never be dropped or downgraded to a plain tap.
struct ConciergeLauncherPress {
    /// How long a press must last before it counts as a hold.
    static let holdThreshold: Duration = .milliseconds(300)

    enum HoldAction: Equatable {
        /// Start in-place push-to-talk dictation.
        case beginPushToTalk
        /// Held without consent: nothing starts yet; release will route to listen.
        case awaitRelease
    }

    enum ReleaseAction: Equatable {
        /// Quick tap — open the Concierge tab.
        case open
        /// Held with consent — stop dictation and send.
        case endPushToTalk
        /// Held without consent — open Concierge in listening mode via the
        /// consent disclosure.
        case listenAfterConsent
    }

    private(set) var pressID: Int?
    private(set) var hasConsent = false
    private(set) var held = false
    private var nextID = 0

    var isPressing: Bool { pressID != nil }

    /// Finger down. Returns the press token to hand back to `holdElapsed`, or nil
    /// if this is a continuation of a press already being tracked.
    mutating func pressBegan(hasConsent: Bool) -> Int? {
        guard pressID == nil else { return nil }
        nextID += 1
        pressID = nextID
        self.hasConsent = hasConsent
        held = false
        return nextID
    }

    /// The hold timer fired. Returns nil if that press already ended.
    mutating func holdElapsed(pressID token: Int) -> HoldAction? {
        guard pressID == token, !held else { return nil }
        held = true
        return hasConsent ? .beginPushToTalk : .awaitRelease
    }

    /// Finger up.
    mutating func pressEnded() -> ReleaseAction {
        defer { pressID = nil; held = false; hasConsent = false }
        guard held else { return .open }
        return hasConsent ? .endPushToTalk : .listenAfterConsent
    }
}
