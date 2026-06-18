import Foundation

/// Minimal 16-bit PCM mono WAV writer. Transcription engines all accept this.
enum WAV {
    static let sampleRate = 16_000

    static func write(_ samples: [Float], to url: URL) throws {
        // Mixing mic + system can sum past full-scale; peak-limit instead of
        // hard-clipping so the audio stays clean for the transcriber.
        var gain: Float = 1
        if let peak = samples.map({ abs($0) }).max(), peak > 0.99 {
            gain = 0.99 / peak
        }
        var pcm = [Int16]()
        pcm.reserveCapacity(samples.count)
        for s in samples {
            let v = max(-1, min(1, s * gain))
            pcm.append(Int16(v * Float(Int16.max)))
        }
        let data = encode(pcm)
        try data.write(to: url, options: .atomic)
    }

    private static func encode(_ pcm: [Int16]) -> Data {
        let byteRate = sampleRate * 2          // mono * 2 bytes
        let dataSize = pcm.count * 2
        var d = Data()

        func append(_ string: String) { d.append(string.data(using: .ascii)!) }
        func appendLE32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func appendLE16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }

        append("RIFF")
        appendLE32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        appendLE32(16)                  // PCM chunk size
        appendLE16(1)                   // PCM format
        appendLE16(1)                   // mono
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(byteRate))
        appendLE16(2)                   // block align
        appendLE16(16)                  // bits per sample
        append("data")
        appendLE32(UInt32(dataSize))
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
