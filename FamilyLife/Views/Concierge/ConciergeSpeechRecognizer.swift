import Foundation
import AVFoundation
import Speech

/// On-device voice dictation for the Concierge composer. Streams a live
/// transcript while the user speaks; nothing leaves the phone until the
/// resulting text is sent as a normal chat message. Privacy-first: prefers
/// on-device recognition where the device supports it.
@MainActor
@Observable
final class ConciergeSpeechRecognizer {
    private(set) var isRecording = false
    private(set) var transcript = ""
    var errorMessage: String?

    /// True once the user has granted both speech + mic access.
    private(set) var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var contextualStrings: [String] = []
    private var receivedFinal = false
    private var lastTranscriptChange = Date()
    private var silenceTask: Task<Void, Never>?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// Intent verbs and household phrases Speech is likely to mangle without a hint.
    /// Combined with household names at start time (capped at 100).
    static let actionHints: [String] = [
        "add to calendar", "make an appointment", "schedule", "reschedule",
        "cancel", "remind me", "to-do", "todo", "add a task", "grocery list",
        "add to the list", "pick up", "drop off", "soccer practice", "dentist",
        "birthday", "anniversary", "key date", "milestone", "chore", "routine",
        "bedtime", "school pickup", "take a note", "jot down",
    ]

    /// Proper nouns are the easiest words for dictation to miss. Supplying the
    /// household's names biases recognition toward what the user is likely to say.
    func setContextualStrings(_ strings: [String]) {
        contextualStrings = Array(Set(strings.filter { !$0.isEmpty })).prefix(100).map { $0 }
    }

    /// Request the two permissions voice input needs. Returns true if both granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speech else { authorized = false; return false }
        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
        authorized = speech && mic
        return authorized
    }

    /// Warm up permissions and the audio graph ahead of a press so `start()` has
    /// almost nothing left to do — this is what stops the first word being clipped
    /// while the mic spins up. Safe to call repeatedly; cheap once warmed.
    func prewarm() async {
        if !authorized { _ = await requestAuthorization() }
        // `prepare()` initializes the engine graph, which pulls in the input
        // node. When there's no usable input route (the Simulator always, or a
        // device whose mic hasn't come up), the input format is 0 Hz and
        // AVAudioEngineGraph::Initialize throws an Obj-C NSException that Swift
        // can't catch — SIGABRT. This fires on every press of the launcher
        // (even a quick tap), so guard the format before touching the graph.
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        // `prepare()` allocates the engine's render resources without activating
        // the session or ducking other audio, so a stray tap won't interrupt music.
        if !audioEngine.isRunning { audioEngine.prepare() }
    }

    /// Begin live dictation. `onReady` fires the instant the mic is actually
    /// capturing (so the UI can say "Listening" only when it's true), and
    /// `onUpdate` fires with the running transcript so the caller can mirror it.
    /// When `detectSilence` is true, `onSilence` fires after a pause with a
    /// non-empty transcript so the chat mic can stop without a second tap.
    func start(
        detectSilence: Bool = false,
        onReady: @escaping () -> Void = {},
        onSilence: @escaping () -> Void = {},
        onUpdate: @escaping (String) -> Void
    ) async {
        guard !isRecording else { return }
        errorMessage = nil
        receivedFinal = false

        if !authorized {
            let ok = await requestAuthorization()
            guard ok else {
                errorMessage = "Microphone and speech access are needed for voice. You can enable them in Settings."
                return
            }
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Voice input isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // playAndRecord + spokenAudio unlocks voice processing (noise
            // suppression, echo cancel) and Bluetooth HFP mics (AirPods).
            // .measurement was quieter in a lab but clips real-world speech.
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.addsPunctuation = true
            let hints = Array(Set(Self.actionHints + contextualStrings)).prefix(100)
            request.contextualStrings = Array(hints)
            guard recognizer.supportsOnDeviceRecognition else {
                errorMessage = "Voice input needs on-device speech, which this iPhone doesn't support. You can type instead."
                return
            }
            request.requiresOnDeviceRecognition = true
            self.request = request

            let input = audioEngine.inputNode
            // Voice processing needs the session active; ignore failure on the
            // Simulator or routes that don't support it.
            try? input.setVoiceProcessingEnabled(true)
            let format = input.outputFormat(forBus: 0)
            // A zero sample-rate / zero-channel format means there's no usable
            // audio input route (common on the Simulator, or a device whose mic
            // route hasn't come up yet). Installing a tap or starting the engine
            // with such a format throws an Obj-C NSException from AVAudioEngine
            // ("<compose failure>") that Swift's do/catch can't catch — it
            // SIGABRTs the whole app. Bail gracefully instead.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "Voice input isn't available on this device."
                stop()
                return
            }
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = ""
            lastTranscriptChange = Date()
            // Mic is live — the caller can now safely prompt the user to speak.
            onReady()

            if detectSilence {
                silenceTask?.cancel()
                silenceTask = Task { [weak self] in
                    while let self, self.isRecording, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(200))
                        let idle = Date().timeIntervalSince(self.lastTranscriptChange)
                        let spoken = !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if spoken, idle >= 1.7 {
                            onSilence()
                            break
                        }
                    }
                }
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        let next = result.bestTranscription.formattedString
                        if next != self.transcript {
                            self.lastTranscriptChange = Date()
                        }
                        self.transcript = next
                        onUpdate(self.transcript)
                        if result.isFinal { self.receivedFinal = true }
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone."
            stop()
        }
    }

    /// End the audio input but give Speech a short window to emit its final,
    /// corrected transcription. Immediate cancellation commonly drops the last
    /// word spoken — especially a person's name at the end of a command.
    func finish() async -> String {
        guard isRecording || audioEngine.isRunning else { return transcript }
        silenceTask?.cancel()
        silenceTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        isRecording = false
        // Keep the session alive until Speech emits isFinal (or we time out).
        let deadline = Date().addingTimeInterval(1.2)
        while !receivedFinal, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }
        let finalTranscript = transcript
        task?.cancel()
        request = nil
        task = nil
        try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return finalTranscript
    }

    /// Stop dictation and tear down the audio graph.
    func stop() {
        guard isRecording || audioEngine.isRunning || request != nil || task != nil else { return }
        silenceTask?.cancel()
        silenceTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
