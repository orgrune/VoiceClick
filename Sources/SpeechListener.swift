import AVFoundation
import Foundation
import Speech

/// Continuously listens to the microphone and emits one "command" per utterance.
/// An utterance ends when the recognizer reports a final result or when the
/// transcript stops changing for `silenceInterval` seconds.
final class SpeechListener {
    var onPartial: ((String) -> Void)?
    var onCommand: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    var silenceInterval: TimeInterval = 0.9

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastText = ""
    private var lastChange = Date()
    private var segmentHandled = false
    private(set) var running = false

    func requestPermissions(_ completion: @escaping (Bool, String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion(false, "Speech recognition not allowed. Enable VoiceClick in System Settings → Privacy & Security → Speech Recognition.")
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async {
                    completion(ok, ok ? "" : "Microphone not allowed. Enable VoiceClick in System Settings → Privacy & Security → Microphone.")
                }
            }
        }
    }

    func start() throws {
        guard !running else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoiceClick", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available on this Mac."])
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "VoiceClick", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input found."])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        running = true
        startTask()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkSilence()
        }
        let mode = recognizer.supportsOnDeviceRecognition ? "on-device" : "server"
        onStatus?("Listening (\(mode))")
    }

    func stop() {
        running = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        lastText = ""
    }

    // MARK: - Recognition task lifecycle

    private func startTask() {
        guard let recognizer else { return }
        task?.cancel()
        task = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        if #available(macOS 13.0, *) {
            req.addsPunctuation = false
        }
        request = req
        lastText = ""
        lastChange = Date()
        segmentHandled = false

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.request === req else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.lastText {
                        self.lastText = text
                        self.lastChange = Date()
                        self.onPartial?(text)
                    }
                    if result.isFinal { self.finishSegment() }
                }
                if error != nil, self.running {
                    // Recognizer gave up (timeout, no speech, etc.). Start a fresh task.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.running, self.request === req { self.startTask() }
                    }
                }
            }
        }
    }

    private func finishSegment() {
        guard !segmentHandled else { return }
        segmentHandled = true
        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onCommand?(text) }
        if running { startTask() }
    }

    private func checkSilence() {
        guard running else { return }
        let idle = Date().timeIntervalSince(lastChange)
        if !segmentHandled, !lastText.isEmpty, idle > silenceInterval {
            finishSegment()
        } else if lastText.isEmpty, idle > 50 {
            // Keep sessions short so server-based recognition never hits its limit.
            startTask()
        }
    }
}
