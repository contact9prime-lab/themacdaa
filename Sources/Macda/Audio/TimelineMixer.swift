import Foundation

/// Additively mixes multiple 16kHz-mono Float streams that both start at t=0.
/// Each source keeps its own write cursor; samples are summed at matching
/// positions so mic + system audio stay roughly time-aligned. The accumulator
/// only ever flushes regions that every active source has reached, so we never
/// transcribe a half-mixed window.
final class TimelineMixer {
    private let lock = NSLock()
    private var buffer: [Float] = []
    private var writeIndex: [Int: Int] = [:]   // source id -> next write position
    private var activeSources: Set<Int> = []

    // Stall tracking: a source that stops delivering (e.g. a dead/wrong mic)
    // must not freeze flushing for the source that IS live.
    private var tick = 0
    private var lastAdvanceTick: [Int: Int] = [:]
    private var lastWriteIndex: [Int: Int] = [:]
    private let stallTicks = 6                 // ~0.6s at the 100ms drain cadence

    func activate(_ source: Int) {
        lock.lock(); defer { lock.unlock() }
        activeSources.insert(source)
        writeIndex[source] = writeIndex[source] ?? 0
        lastAdvanceTick[source] = tick
    }

    func add(_ frames: [Float], source: Int) {
        guard !frames.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var idx = writeIndex[source] ?? 0
        let needed = idx + frames.count
        if buffer.count < needed {
            buffer.append(contentsOf: repeatElement(0, count: needed - buffer.count))
        }
        for f in frames {
            buffer[idx] += f
            idx += 1
        }
        writeIndex[source] = idx
    }

    /// Returns the fully-mixed samples not yet consumed, advancing the read head.
    /// `committed` = how far every *live* source has written past. Sources that
    /// have stalled (no new audio for ~0.6s) are excluded so a single dead mic
    /// can't block transcription of the audio that IS arriving.
    func drainCommitted() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard !activeSources.isEmpty else { return [] }
        tick += 1

        // Update per-source advance tracking.
        for s in activeSources {
            let wi = writeIndex[s] ?? 0
            if wi != (lastWriteIndex[s] ?? -1) {
                lastWriteIndex[s] = wi
                lastAdvanceTick[s] = tick
            }
        }

        let live = activeSources.filter { tick - (lastAdvanceTick[$0] ?? tick) <= stallTicks }
        let pool = live.isEmpty ? activeSources : live
        let committed = pool.compactMap { writeIndex[$0] }.min() ?? 0
        guard committed > 0 else { return [] }

        let out = Array(buffer[0..<committed])
        buffer.removeFirst(committed)
        // Clamp so an excluded (stalled) source doesn't go negative; when it
        // resumes it simply writes at the current head.
        for s in activeSources { writeIndex[s] = max(0, (writeIndex[s] ?? 0) - committed) }
        return out
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        writeIndex.removeAll()
        activeSources.removeAll()
        lastAdvanceTick.removeAll()
        lastWriteIndex.removeAll()
        tick = 0
    }
}
