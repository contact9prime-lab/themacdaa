import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// A lightweight, always-on microphone monitor used for Auto-Listen. It does no
/// transcription — it just watches the input level and fires `onSpeech` once it
/// hears sustained sound, so AppState can kick off a real recording session.
/// Runs only while Macda is idle (not already listening).
final class AutoListenMonitor {
    var onSpeech: (() -> Void)?

    private let engine = AVAudioEngine()
    private var running = false
    private var loudSeconds: Double = 0
    private let triggerSeconds = 0.5
    private var threshold: Float = 0.02
    private var micDeviceUID = ""

    @discardableResult
    func start(threshold: Float, micDeviceUID: String) -> Bool {
        guard !running else { return true }
        self.threshold = max(0.012, threshold * 1.3)
        self.micDeviceUID = micDeviceUID
        loudSeconds = 0

        let input = engine.inputNode
        if let deviceID = AudioDevices.deviceID(forUID: micDeviceUID), let unit = input.audioUnit {
            var dev = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return false }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
            running = true
            return true
        } catch {
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
        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { let s = ch[0][i]; sum += s * s }
        let rms = (sum / Float(n)).squareRoot()
        let seconds = Double(n) / buffer.format.sampleRate

        if rms > threshold {
            loudSeconds += seconds
            if loudSeconds >= triggerSeconds {
                loudSeconds = 0
                let fire = onSpeech
                DispatchQueue.main.async { fire?() }
            }
        } else {
            loudSeconds = max(0, loudSeconds - seconds)   // decay
        }
    }
}
