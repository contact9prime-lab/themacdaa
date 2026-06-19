import Foundation
import AVFoundation

/// Plays back retained audio clips (a speaker's sample) so you can hear who said
/// it before tagging. Tracks the currently-playing path for UI state.
@MainActor
final class AudioPlayback: NSObject, ObservableObject {
    static let shared = AudioPlayback()
    @Published var playingPath: String?
    private var player: AVAudioPlayer?
    private var queue: [String] = []
    private var sequenceID: String?

    func toggle(_ path: String) {
        if playingPath == path { stop() } else { play(path) }
    }

    /// Play a list of clips back-to-back (a meeting recording). `id` lets the UI
    /// show play/stop state for the whole sequence.
    func playSequence(_ paths: [String], id: String) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        if sequenceID == id { stop(); return }
        stop()
        sequenceID = id
        queue = Array(existing.dropFirst())
        play(existing[0], partOfSequence: true)
        playingPath = id
    }

    private func play(_ path: String, partOfSequence: Bool) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player?.delegate = self
        _ = player?.play()
    }

    func play(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            playingPath = nil
            return
        }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player?.delegate = self
        playingPath = (player?.play() == true) ? path : nil
    }

    func stop() {
        player?.stop()
        player = nil
        playingPath = nil
        queue = []
        sequenceID = nil
    }

    func available(_ path: String) -> Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }
}

extension AudioPlayback: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Continue a sequence if more clips remain.
            if self.sequenceID != nil, !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.play(next, partOfSequence: true)
            } else {
                self.playingPath = nil
                self.sequenceID = nil
            }
        }
    }
}
