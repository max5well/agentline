import AVFoundation
import SwiftUI

// Fetches and plays voice samples for the picker and profile editor.
@MainActor
@Observable
final class VoicePreviewPlayer {
    private(set) var loadingId: String?
    private(set) var playingId: String?
    var errorMessage: String?
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]

    func play(id: String, voice: String, style: String?) async {
        if playingId == id {
            stop()
            return
        }
        stop()
        loadingId = id
        errorMessage = nil
        defer { loadingId = nil }
        do {
            // Voice rows preview with the current style and style rows with
            // the current voice, so cache by the actual combination.
            let key = "\(voice)|\(style ?? "")"
            let data: Data
            if let cached = cache[key] {
                data = cached
            } else {
                data = try await BackendClient(config: .current).voicePreview(voice: voice, style: style)
                cache[key] = data
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            self.player = player
            playingId = id
            player.play()
            // Reset the indicator when the clip ends.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(player.duration + 0.2))
                if self?.playingId == id { self?.playingId = nil }
            }
        } catch {
            errorMessage = "Preview failed — are you signed in?"
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }
}
