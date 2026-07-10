import SwiftUI
import UIKit

/// App-wide channel for requesting the concierge chat with a seeded prompt.
/// Feature views call `ask(_:)`; MainTabView switches to the Concierge tab and
/// ConciergeView presents the chat (or the paywall, if not premium).
@Observable
final class ConciergeLaunch {
    /// Bumped on every request so observers fire even for a listen-only launch
    /// (which carries no prompt). Non-zero means a request is pending.
    private(set) var requestID = 0
    private(set) var pendingPrompt: String?
    private(set) var pendingAutoListen = false

    struct Request {
        let prompt: String?
        let autoListen: Bool
    }

    /// Open the concierge chat seeded with `prompt`.
    func ask(_ prompt: String) {
        pendingPrompt = prompt
        pendingAutoListen = false
        requestID += 1
    }

    /// Open the concierge chat straight into voice dictation (no seed prompt).
    func listen() {
        pendingPrompt = nil
        pendingAutoListen = true
        requestID += 1
    }

    /// Read and clear the pending request.
    func consume() -> Request? {
        guard requestID != 0 else { return nil }
        let request = Request(prompt: pendingPrompt, autoListen: pendingAutoListen)
        pendingPrompt = nil
        pendingAutoListen = false
        requestID = 0
        return request
    }
}

/// Drives the home-screen "push to talk" launcher: hold the ✨ button to
/// dictate, release to send straight to the concierge in the background — no
/// navigation. The message and its reply are persisted server-side, so they
/// show up later in the chat history. Built for quick brain-dumps of to-dos
/// or updates without opening the app proper.
@MainActor
@Observable
final class PushToTalkController {
    enum Phase: Equatable { case idle, starting, listening, sending }
    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    /// Brief status shown after a send (confirmation or error); auto-clears.
    var banner: String?
    /// Bumped after a note lands successfully so surfaces like Home can
    /// silently refresh — the concierge may have just added tasks/events/items.
    private(set) var completedSends = 0

    private let recognizer = ConciergeSpeechRecognizer()
    /// Chains repeated dictations into one running thread within a session.
    private var conversationId: Int?

    var isActive: Bool { phase != .idle }

    /// Warm the mic + permissions the moment a press begins, before we know if
    /// it's a tap or a hold — cuts the spin-up lag that clips the first word.
    func prewarm() {
        guard phase == .idle else { return }
        Task { await recognizer.prewarm() }
    }

    /// Finger held past the tap threshold — start listening. Shows a brief
    /// "getting ready" state, then flips to a live "listening" cue with a haptic
    /// only once the mic is actually capturing, so users don't speak too early.
    func begin() {
        guard phase == .idle else { return }
        phase = .starting
        transcript = ""
        banner = nil
        Task {
            await recognizer.start { [weak self] in
                guard let self else { return }
                // Finger already lifted while the mic was spinning up — tear back
                // down instead of leaving a live mic with no listener.
                guard self.phase == .starting else { self.recognizer.stop(); return }
                self.phase = .listening
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } onUpdate: { [weak self] text in
                self?.transcript = text
            }
            // start() surfaces errorMessage only on an immediate failure.
            if let err = recognizer.errorMessage {
                banner = err
                phase = .idle
            }
        }
    }

    /// Finger lifted — stop listening and fire the message off to the AI. Also
    /// handles a release during `.starting` (mic still warming up).
    func end(api: APIService) {
        guard phase == .listening || phase == .starting else { return }
        // Flip out of .starting first so a late onReady tears the mic back down.
        let wasListening = phase == .listening
        phase = .sending
        recognizer.stop()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        guard wasListening, !text.isEmpty else { phase = .idle; return }
        Task { await send(text, api: api) }
    }

    /// Abort a live dictation without sending.
    func cancel() {
        guard phase == .listening || phase == .starting else { return }
        phase = .idle
        recognizer.stop()
        transcript = ""
    }

    private func send(_ text: String, api: APIService) async {
        do {
            for try await event in api.conciergeMessageStream(text, conversationId: conversationId) {
                if case .done(let response) = event { conversationId = response.conversationId }
            }
            banner = "Sent to your concierge"
            completedSends += 1
        } catch {
            banner = "Couldn't send — try again"
        }
        phase = .idle
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if phase == .idle { banner = nil }
        }
    }
}

/// Floating concierge launcher. A quick tap opens the concierge tab; press and
/// hold turns it into a walkie-talkie — dictate while held, release to send.
struct ConciergeLauncherButton: View {
    @Environment(APIService.self) private var api
    let ptt: PushToTalkController
    /// Quick tap (no hold) → open the concierge tab.
    let onOpen: () -> Void

    @State private var pressStart: Date?
    @State private var listening = false

    private var isListening: Bool { ptt.phase == .listening || ptt.phase == .starting }

    var body: some View {
        Image(systemName: isListening ? "waveform" : "sparkles")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(isListening ? AccentTheme.rose.color : AccentTheme.saffron.color, in: Circle())
            .scaleEffect(isListening ? 1.12 : 1)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isListening)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressStart == nil else { return }
                        let start = Date()
                        pressStart = start
                        // Warm the mic immediately so a hold starts capturing fast.
                        ptt.prewarm()
                        // Promote to dictation once held past a tap.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.3))
                            if pressStart == start, !listening {
                                listening = true
                                ptt.begin()
                            }
                        }
                    }
                    .onEnded { _ in
                        let held = listening
                        pressStart = nil
                        listening = false
                        if held {
                            ptt.end(api: api)
                        } else {
                            onOpen()
                        }
                    }
            )
            .accessibilityLabel("AI concierge")
            .accessibilityHint("Tap to open, or touch and hold to speak a quick note")
    }
}

/// Centered feedback for push-to-talk: live transcript while listening, a
/// spinner while sending, and a brief confirmation/error banner after.
struct PushToTalkOverlay: View {
    let ptt: PushToTalkController

    var body: some View {
        VStack {
            Spacer()
            content
                .padding(.bottom, 150)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: ptt.phase)
        .animation(.easeInOut(duration: 0.2), value: ptt.transcript)
    }

    @ViewBuilder private var content: some View {
        switch ptt.phase {
        case .starting:
            card {
                HStack(spacing: 10) {
                    ProgressView().tint(AccentTheme.rose.color)
                    Text("Getting ready…")
                        .foregroundStyle(WarmPalette.ink2)
                        .font(.flSubheadline.weight(.medium))
                }
            }
        case .listening:
            card {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(AccentTheme.rose.color)
                    Text(ptt.transcript.isEmpty ? "Listening…" : ptt.transcript)
                        .foregroundStyle(WarmPalette.ink1)
                        .font(.flSubheadline.weight(.medium))
                        .lineLimit(3)
                }
            }
        case .sending:
            card {
                HStack(spacing: 10) {
                    ProgressView().tint(WarmPalette.ink2)
                    Text("Sending to your concierge…")
                        .foregroundStyle(WarmPalette.ink2)
                        .font(.flSubheadline.weight(.medium))
                }
            }
        case .idle:
            if let banner = ptt.banner {
                card {
                    Text(banner)
                        .foregroundStyle(WarmPalette.ink1)
                        .font(.flSubheadline.weight(.medium))
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WarmPalette.ink4.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A small toolbar entry that hands a contextual prompt to the concierge.
/// Hidden until the user opts into the AI concierge.
struct AskButlerButton: View {
    @Environment(ConciergeLaunch.self) private var launch
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false
    let prompt: String

    var body: some View {
        if aiConciergeEnabled {
            Button { launch.ask(prompt) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AccentTheme.saffron.color)
            }
            .accessibilityLabel("Ask your concierge")
        }
    }
}

/// Opt-in / intro screen for the AI concierge. Reached discreetly from More.
/// Until enabled here, every AI surface (floating launcher, contextual ✨
/// buttons) stays hidden.
struct ConciergeIntroView: View {
    @Environment(SubscriptionService.self) private var subscription
    @AppStorage("aiConciergeEnabled") private var aiConciergeEnabled = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AccentTheme.saffron.color)
                    Text("AI Concierge")
                        .font(.flScreenTitle)
                        .foregroundStyle(WarmPalette.ink1)
                    Text("A warm daily brief of what needs you across the family, plus a chat that can look things up and add to your calendar, lists, and budget.")
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink3)
                }

                Toggle(isOn: $aiConciergeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Concierge")
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Text(aiConciergeEnabled
                             ? "A ✨ button now appears across from chat."
                             : "Adds a discreet ✨ launcher to your home screen.")
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .tint(AccentTheme.saffron.color)
                .padding(14)
                .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))

                VStack(alignment: .leading, spacing: 6) {
                    Label("The daily brief is free.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WarmPalette.ink2)
                    Label(subscription.isPremium
                          ? "Concierge chat is active on your household."
                          : "Concierge chat needs Premium.",
                          systemImage: subscription.isPremium ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundStyle(WarmPalette.ink2)
                }
                .font(.flFootnote.weight(.medium))
            }
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 8)
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle("AI Concierge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}
