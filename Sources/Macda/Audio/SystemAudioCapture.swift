import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

/// Captures system / application audio (everyone else on the call) using
/// ScreenCaptureKit. Requires Screen Recording permission (macOS 13+).
/// Configured to deliver 16kHz mono Float32 so it drops straight into the mixer.
final class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    var onFrames: (([Float]) -> Void)?
    var onError: ((String) -> Void)?

    private let targetSampleRate: Double
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "macda.audio.system")

    init(targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Macda", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No display found for system-audio capture."])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true     // don't record Macda's own sounds
        // Keep video minimal — we only want the audio track.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let frames = Self.extractFloatMono(sampleBuffer) else { return }
        if !frames.isEmpty { onFrames?(frames) }
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("System audio stopped: \(error.localizedDescription)")
    }

    /// Pulls Float32 mono samples out of a CoreMedia audio buffer.
    private static func extractFloatMono(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&abl)
        guard let first = buffers.first, let data = first.mData else { return nil }
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let ptr = data.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}
