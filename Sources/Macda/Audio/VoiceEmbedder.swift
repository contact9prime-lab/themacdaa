import Foundation
import Accelerate

/// Computes a compact acoustic "voiceprint" from 16kHz-mono samples: a
/// log-mel spectrogram reduced to per-band mean+std, L2-normalized. Good enough
/// to tell a handful of speakers apart and match the same voice across calls.
/// Not a biometric — it's a best-effort similarity fingerprint.
enum VoiceEmbedder {
    private static let fftSize = 512
    private static let log2n = vDSP_Length(9)            // log2(512)
    private static let frameSize = 400                   // 25ms @ 16kHz
    private static let hop = 160                          // 10ms
    private static let melBands = 26
    private static let half = fftSize / 2

    private static let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

    private static let hann: [Float] = {
        var w = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&w, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        return w
    }()

    private static let filterbank: [[Float]] = makeMelFilterbank()

    /// Returns a 52-dim normalized embedding, or nil if there isn't enough audio.
    static func embed(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameSize, let setup = fftSetup else { return [] }

        var melSum = [Float](repeating: 0, count: melBands)
        var melSqSum = [Float](repeating: 0, count: melBands)
        var frameCount = 0

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var windowed = [Float](repeating: 0, count: fftSize)
        var power = [Float](repeating: 0, count: half)

        var pos = 0
        while pos + frameSize <= samples.count {
            for i in 0..<frameSize { windowed[i] = samples[pos + i] * hann[i] }
            for i in frameSize..<fftSize { windowed[i] = 0 }

            windowed.withUnsafeMutableBufferPointer { wb in
                wb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cplx in
                    real.withUnsafeMutableBufferPointer { rp in
                        imag.withUnsafeMutableBufferPointer { ip in
                            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                            vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(half))
                            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                            vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
                        }
                    }
                }
            }

            for b in 0..<melBands {
                var e: Float = 0
                vDSP_dotpr(power, 1, filterbank[b], 1, &e, vDSP_Length(half))
                let le = log(1 + e)
                melSum[b] += le
                melSqSum[b] += le * le
            }
            frameCount += 1
            pos += hop
        }

        guard frameCount > 0 else { return [] }
        let fc = Float(frameCount)
        var emb = [Float]()
        emb.reserveCapacity(melBands * 2)
        for b in 0..<melBands {
            let mean = melSum[b] / fc
            let variance = max(0, melSqSum[b] / fc - mean * mean)
            emb.append(mean)
            emb.append(variance.squareRoot())
        }
        return l2normalized(emb)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot   // inputs are L2-normalized
    }

    /// Mean of several embeddings, renormalized — a speaker's enrolled print.
    static func centroid(_ embeddings: [[Float]]) -> [Float] {
        let valid = embeddings.filter { !$0.isEmpty }
        guard let dim = valid.first?.count, dim > 0 else { return [] }
        var sum = [Float](repeating: 0, count: dim)
        for e in valid where e.count == dim {
            vDSP_vadd(sum, 1, e, 1, &sum, 1, vDSP_Length(dim))
        }
        return l2normalized(sum)
    }

    // MARK: - Helpers

    private static func l2normalized(_ v: [Float]) -> [Float] {
        var out = v
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        if norm > 1e-6 { var n = norm; vDSP_vsdiv(v, 1, &n, &out, 1, vDSP_Length(v.count)) }
        return out
    }

    private static func makeMelFilterbank() -> [[Float]] {
        let sampleRate: Float = 16000
        func hzToMel(_ f: Float) -> Float { 2595 * log10(1 + f / 700) }
        func melToHz(_ m: Float) -> Float { 700 * (pow(10, m / 2595) - 1) }

        let lowMel = hzToMel(0), highMel = hzToMel(sampleRate / 2)
        let points = (0...(melBands + 1)).map { i -> Float in
            melToHz(lowMel + (highMel - lowMel) * Float(i) / Float(melBands + 1))
        }
        let bins = points.map { Int(floor(($0 / (sampleRate / 2)) * Float(half - 1))) }

        var bank = [[Float]](repeating: [Float](repeating: 0, count: half), count: melBands)
        for m in 1...melBands {
            let left = bins[m - 1], center = bins[m], right = bins[m + 1]
            for k in max(0, left)..<max(left + 1, center) where k < half && center > left {
                bank[m - 1][k] = Float(k - left) / Float(center - left)
            }
            for k in center..<max(center + 1, right) where k < half && right > center {
                bank[m - 1][k] = Float(right - k) / Float(right - center)
            }
        }
        return bank
    }
}
