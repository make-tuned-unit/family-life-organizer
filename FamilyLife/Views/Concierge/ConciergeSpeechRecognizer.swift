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

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

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
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
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

    /// Stop dictation and tear down the audio graph.
    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
