import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// Captures microphone (+ optional system audio), mixes both at 16kHz mono,
/// computes a live level for the mascot animation, and cuts the stream into
/// chunks on natural silence gaps (or a max length) for batched transcription.
final class AudioCaptureEngine {
    // Callbacks (may fire on a background queue).
    var onLevel: ((Float) -> Void)?
    var onChunk: ((AudioChunk) -> Void)?
    var onPreview: ((AudioChunk) -> Void)?   // live, in-progress transcript for the bubble
    var onSilenceTimeout: (() -> Void)?
    var onError: ((String) -> Void)?

    private let micSourceID = 0
    private let systemSourceID = 1

    private let engine = AVAudioEngine()
    private let mixer = TimelineMixer()
    private var systemCapture: SystemAudioCapture?
    private let queue = DispatchQueue(label: "macda.audio.process")
    private var timer: DispatchSourceTimer?

    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Double(WAV.sampleRate),
                                             channels: 1,
                                             interleaved: false)!

    // Chunking / silence state (all touched only on `queue`).
    private var currentChunk: [Float] = []
    private var chunkIndex = 0
    private var hasSpeech = false
    private var trailingSilence: Double = 0
    private var totalSilenceSinceSpeech: Double = 0
    private var previewElapsed: Double = 0
    private let previewInterval: Double = 1.5   // refresh the live bubble every ~1.5s

    private var settings = Settings()
    private var recordingsDir = Store().recordingsDir
    private var sessionID = "s0"

    func start(sources: AudioSourceOptions) async throws {
        settings = Settings.load()
        reset()

        if sources.contains(.microphone) {
            try await ensureMicPermission()
            try startMic()
        }
        if sources.contains(.system) {
            try await startSystem()
        }
        startProcessingLoop()
    }

    func stop() {
        timer?.cancel(); timer = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        systemCapture?.stop()
        systemCapture = nil
    }

    /// Called on stop to emit whatever audio remains as a final chunk.
    func flushPendingChunk() -> AudioChunk? {
        queue.sync {
            guard hasSpeech, !currentChunk.isEmpty else { currentChunk.removeAll(); return nil }
            return emitChunkLocked()
        }
    }

    // MARK: - Microphone

    private func ensureMicPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw micError("Microphone access was denied.") }
        default:
            throw micError("Microphone access is off. Enable it in System Settings → Privacy → Microphone.")
        }
    }

    private func startMic() throws {
        let input = engine.inputNode

        // Point the engine at the chosen input device (not just the default).
        if let deviceID = AudioDevices.deviceID(forUID: settings.micDeviceUID),
           let unit = input.audioUnit {
            var dev = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw micError("Selected microphone has no input. Pick another in Settings → Listening.")
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        mixer.activate(micSourceID)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frames = self.resample(buffer)
            if !frames.isEmpty { self.mixer.add(frames, source: self.micSourceID) }
        }
        engine.prepare()
        try engine.start()
    }

    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let converter else { return floatMono(buffer) }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }

        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if err != nil { return [] }
        return Array(UnsafeBufferPointer(start: out.floatChannelData?[0], count: Int(out.frameLength)))
    }

    private func floatMono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let ch = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
    }

    // MARK: - System audio

    private func startSystem() async throws {
        let capture = SystemAudioCapture(targetSampleRate: Double(WAV.sampleRate))
        capture.onFrames = { [weak self] frames in
            guard let self else { return }
            self.mixer.add(frames, source: self.systemSourceID)
        }
        capture.onError = { [weak self] msg in self?.onError?(msg) }
        mixer.activate(systemSourceID)
        try await capture.start()
        systemCapture = capture
    }

    // MARK: - Processing loop (level, silence, chunking)

    private func startProcessingLoop() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let block = mixer.drainCommitted()
        guard !block.isEmpty else { return }

        let rms = Self.rms(block)
        let level = min(1, rms * 12)            // scaled for the animation
        onLevel?(level)

        let seconds = Double(block.count) / Double(WAV.sampleRate)
        let isQuiet = rms < settings.silenceThreshold

        currentChunk.append(contentsOf: block)

        if isQuiet {
            trailingSilence += seconds
            totalSilenceSinceSpeech += seconds
        } else {
            hasSpeech = true
            trailingSilence = 0
            totalSilenceSinceSpeech = 0
        }

        let chunkSeconds = Double(currentChunk.count) / Double(WAV.sampleRate)
        previewElapsed += seconds

        // Cut a chunk when speech is followed by a natural pause, or it hits the
        // length cap. Each emitted chunk is transcribed in parallel (capped by
        // settings.parallelTranscriptions) so we never wait on the previous one.
        if hasSpeech && (trailingSilence >= 0.7 || chunkSeconds >= effectiveMaxChunk) {
            if let chunk = emitChunkLocked() { onChunk?(chunk) }
            previewElapsed = 0
        } else if hasSpeech && chunkSeconds >= 1.2 && previewElapsed >= previewInterval {
            // Live preview: transcribe the in-progress chunk for the bubble.
            previewElapsed = 0
            if let preview = writePreviewLocked() { onPreview?(preview) }
        }

        // Whole call went quiet for too long → ask AppState to auto-stop.
        if settings.autoStopOnSilence && totalSilenceSinceSpeech >= settings.silenceTimeout {
            onSilenceTimeout?()
            totalSilenceSinceSpeech = 0
        }
    }

    /// Writes `currentChunk` to a WAV file and resets chunk state. Caller holds `queue`.
    private func emitChunkLocked() -> AudioChunk? {
        defer {
            currentChunk.removeAll(keepingCapacity: true)
            hasSpeech = false
            trailingSilence = 0
        }
        guard currentChunk.count > WAV.sampleRate / 4 else { return nil } // ignore < 0.25s
        let idx = chunkIndex; chunkIndex += 1
        let url = recordingsDir.appendingPathComponent("chunk-\(sessionID)-\(idx).wav")
        do {
            try WAV.write(currentChunk, to: url)
            let dur = Double(currentChunk.count) / Double(WAV.sampleRate)
            let embedding = VoiceEmbedder.embed(currentChunk)   // voiceprint for speaker ID
            return AudioChunk(url: url, index: idx, duration: dur, embedding: embedding)
        } catch {
            onError?("Failed writing audio chunk: \(error.localizedDescription)")
            return nil
        }
    }

    /// Snapshot the in-progress chunk to a fixed file for a live transcript.
    private func writePreviewLocked() -> AudioChunk? {
        guard currentChunk.count > WAV.sampleRate / 2 else { return nil }
        let url = recordingsDir.appendingPathComponent("preview-\(sessionID).wav")
        do {
            try WAV.write(currentChunk, to: url)
            return AudioChunk(url: url, index: -1, duration: Double(currentChunk.count) / Double(WAV.sampleRate))
        } catch { return nil }
    }

    private func reset() {
        mixer.reset()
        previewElapsed = 0
        currentChunk.removeAll()
        chunkIndex = 0
        hasSpeech = false
        trailingSilence = 0
        totalSilenceSinceSpeech = 0
        recordingsDir = Store().recordingsDir
        sessionID = String(UUID().uuidString.prefix(8))
    }

    /// Ollama multimodal audio requires snippets under 30s; cap there with margin.
    private var effectiveMaxChunk: Double {
        settings.transcriptionProvider == .ollamaAudio
            ? min(settings.maxChunkSeconds, 28)
            : settings.maxChunkSeconds
    }

    private func micError(_ message: String) -> NSError {
        NSError(domain: "Macda", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}
