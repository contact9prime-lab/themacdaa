import Foundation
import AVFoundation

/// Text-to-speech so Macda can talk back in talking mode.
@MainActor
final class Speaker {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: clean)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.prefersAssistiveTechnologySettings = false
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

/// Records a short clip from the default mic to a 16kHz mono WAV (for dictation).
final class SimpleRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var url: URL?

    @discardableResult
    func start() -> Bool {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("macda-dictation.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.record()
        recorder = r
        self.url = url
        return true
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return url
    }
}
