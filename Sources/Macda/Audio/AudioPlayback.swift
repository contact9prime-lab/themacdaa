import Foundation
import AVFoundation

/// Plays back retained audio clips (a speaker's sample) so you can hear who said
/// it before tagging. Tracks the currently-playing path for UI state.
@MainActor
final class AudioPlayback: NSObject, ObservableObject {
    static let shared = AudioPlayback()
    @Published var playingPath: String?
    private var player: AVAudioPlayer?

    func toggle(_ path: String) {
        if playingPath == path { stop() } else { play(path) }
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
    }

    func available(_ path: String) -> Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }
}

extension AudioPlayback: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingPath = nil }
    }
}
