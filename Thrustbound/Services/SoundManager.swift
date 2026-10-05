import AVFoundation
import Foundation

enum SoundEffect: String, CaseIterable {
    case star
    case fuel
    case key
    case door
    case crash
    case land
    case click
    case bump
    case lowFuel = "lowfuel"
}

/// Plays the bundled WAV effects plus a looping engine sound.
final class SoundManager {
    static let shared = SoundManager()

    var enabled = true {
        didSet {
            if !enabled { stopThrustNow() }
        }
    }

    private var pools: [SoundEffect: [AVAudioPlayer]] = [:]
    private var thrustPlayer: AVAudioPlayer?
    private var thrustOn = false
    private var prepared = false

    private init() {}

    func prepare() {
        guard !prepared else { return }
        prepared = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            var pool: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    pool.append(player)
                }
            }
            pools[effect] = pool
        }
        if let url = Bundle.main.url(forResource: "thrust", withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            thrustPlayer = player
        }
    }

    func play(_ effect: SoundEffect, volume: Float = 1) {
        guard enabled, let pool = pools[effect], !pool.isEmpty else { return }
        let player = pool.first(where: { !$0.isPlaying }) ?? pool[0]
        player.currentTime = 0
        player.volume = max(0, min(1, volume))
        player.play()
    }

    func setThrust(_ on: Bool) {
        let wanted = on && enabled
        guard wanted != thrustOn, let player = thrustPlayer else { return }
        thrustOn = wanted
        if wanted {
            if !player.isPlaying {
                player.currentTime = 0
                player.play()
            }
            player.setVolume(0.5, fadeDuration: 0.05)
        } else {
            player.setVolume(0, fadeDuration: 0.12)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, !self.thrustOn else { return }
                self.thrustPlayer?.pause()
            }
        }
    }

    private func stopThrustNow() {
        thrustOn = false
        thrustPlayer?.volume = 0
        thrustPlayer?.pause()
    }
}
