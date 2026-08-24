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

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

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
    func start(onReady: @escaping () -> Void = {}, onUpdate: @escaping (String) -> Void) async {
        guard !isRecording else { return }
        errorMessage = nil

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
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.addsPunctuation = true
            request.contextualStrings = contextualStrings + ["key date", "birthday", "anniversary", "milestone"]
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = audioEngine.inputNode
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
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = ""
            // Mic is live — the caller can now safely prompt the user to speak.
            onReady()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        onUpdate(self.transcript)
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
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? await Task.sleep(for: .milliseconds(450))
        let finalTranscript = transcript
        task?.cancel()
        request = nil
        task = nil
        return finalTranscript
    }

    /// Stop dictation and tear down the audio graph.
    func stop() {
        guard isRecording || audioEngine.isRunning || request != nil || task != nil else { return }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
