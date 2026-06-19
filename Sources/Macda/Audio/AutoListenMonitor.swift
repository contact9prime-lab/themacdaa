import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import MacdaObjC

/// Always-on microphone level monitor for Auto-Listen. No transcription — it
/// just watches the input level on the user's chosen mic and fires `onSpeech`
/// once it hears sustained sound, so AppState can start a real session.
final class AutoListenMonitor {
    var onSpeech: (() -> Void)?

    private var engine = AVAudioEngine()
    private var running = false
    private var loudSeconds: Double = 0
    private let triggerSeconds = 0.5
    private var threshold: Float = 0.02

    // Periodic level logging so we can diagnose a non-triggering mic.
    private var peakRMS: Float = 0
    private var sinceLog: Double = 0

    @discardableResult
    func start(threshold: Float, micDeviceUID: String) -> Bool {
        guard !running else { return true }
        self.threshold = max(0.003, threshold)   // floor just above silence
        loudSeconds = 0; peakRMS = 0; sinceLog = 0

        // Make the chosen mic the system default, then monitor the default input
        // (reliable). This way it hears you where you actually speak.
        if !micDeviceUID.isEmpty { AudioDevices.makeDefaultInput(uid: micDeviceUID) }
        engine = AVAudioEngine()
        if installTap() {
            Log.info("Auto-listen monitor started (threshold \(self.threshold)).")
            return true
        }
        engine = AVAudioEngine()
        return installTap()
    }

    private func installTap() -> Bool {
        let input = engine.inputNode
        input.removeTap(onBus: 0)

        let candidates = [input.outputFormat(forBus: 0), input.inputFormat(forBus: 0)]
            .filter { $0.sampleRate > 0 && $0.channelCount > 0 }
        var installed = false
        for fmt in candidates {
            input.removeTap(onBus: 0)
            var tapError: NSError?
            let ok = MacdaTryCatch({
                input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buffer, _ in
                    self?.process(buffer)
                }
            }, &tapError)
            if ok { installed = true; break }
            else { Log.error("Auto-listen tap failed (\(Int(fmt.sampleRate))Hz): \(tapError?.localizedDescription ?? "?")") }
        }
        guard installed else { return false }
        do {
            engine.prepare()
            try engine.start()
            running = true
            return true
        } catch {
            Log.error("Auto-listen engine start failed: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            running = false
            return false
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        loudSeconds = 0
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        if let ch = buffer.floatChannelData {
            for i in 0..<n { let s = ch[0][i]; sum += s * s }
        } else if let ch = buffer.int16ChannelData {
            for i in 0..<n { let s = Float(ch[0][i]) / Float(Int16.max); sum += s * s }
        } else {
            return
        }
        let rms = (sum / Float(n)).squareRoot()
        let seconds = Double(n) / buffer.format.sampleRate

        // Periodically log the loudest level we've seen vs the threshold.
        peakRMS = max(peakRMS, rms)
        sinceLog += seconds
        if sinceLog >= 4 {
            Log.info(String(format: "Auto-listen level: peak rms %.4f (threshold %.4f)", peakRMS, threshold))
            peakRMS = 0; sinceLog = 0
        }

        if rms > threshold {
            loudSeconds += seconds
            if loudSeconds >= triggerSeconds {
                loudSeconds = 0
                let fire = onSpeech
                DispatchQueue.main.async { fire?() }
            }
        } else {
            loudSeconds = max(0, loudSeconds - seconds)
        }
    }
}
