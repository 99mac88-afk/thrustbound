import SpriteKit
import SwiftUI

struct LevelResult {
    let stars: Int
    let time: Double
    let fuelLeft: Double
    let par: Double
    let update: RecordUpdate

    var underPar: Bool { time <= par }
}

/// HUD values change many times a second, so they live in their own object
/// and only the HUD view observes them.
@MainActor
final class HUDModel: ObservableObject {
    @Published var state = HUDState()
}

/// Glue between the SpriteKit scene and the SwiftUI screens for one play session.
@MainActor
final class GameSession: ObservableObject {
    enum Phase: Equatable {
        case playing
        case paused
        case crashed
        case won
        case outOfFuel
    }

    @Published private(set) var phase: Phase = .playing
    @Published private(set) var levelIndex: Int
    @Published private(set) var showIntro = true
    @Published private(set) var result: LevelResult?
    @Published private(set) var attempts = 1

    let hud: HUDModel
    let scene: GameScene
    let app: AppModel
    private var loadToken = 0

    var level: LevelData { app.levels[levelIndex] }
    /// Text in the player's language.
    var s: L10n { app.s }
    var levelName: String { s.name(level) }
    var levelHint: String { s.hint(level) }
    var worldInfo: WorldInfo? { app.world(for: level) }
    var hasNextLevel: Bool { levelIndex + 1 < app.levels.count }
    var levelLabel: String {
        let indices = app.levelIndices(inWorld: level.world)
        let number = (indices.firstIndex(of: levelIndex) ?? 0) + 1
        return "\(level.world + 1)-\(number)"
    }

    init(app: AppModel, levelIndex: Int) {
        self.app = app
        self.levelIndex = max(0, min(levelIndex, app.levels.count - 1))
        hud = HUDModel()
        scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.session = self
        scene.swapControls = app.swapControls
        scene.demoMode = app.launch.demo
        loadCurrent()
    }

    private func loadCurrent() {
        loadToken += 1
        phase = .playing
        result = nil
        showIntro = true
        hud.state = HUDState()
        scene.swapControls = app.swapControls
        scene.strings = app.s
        scene.load(level: level, world: worldInfo)
        let token = loadToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard let self = self, self.loadToken == token else { return }
            self.hideIntro()
        }
    }

    private func hideIntro() {
        guard showIntro else { return }
        withAnimation(.easeOut(duration: 0.35)) { showIntro = false }
    }

    // MARK: - Player actions

    func restart() {
        attempts += 1
        loadCurrent()
    }

    func nextLevel() {
        guard hasNextLevel else { return }
        levelIndex += 1
        attempts = 1
        loadCurrent()
    }

    func pause() {
        guard phase == .playing, scene.canPause else { return }
        scene.setGamePaused(true)
        withAnimation(.easeOut(duration: 0.2)) { phase = .paused }
    }

    func resume() {
        guard phase == .paused else { return }
        scene.setGamePaused(false)
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    func quitToLevels() {
        scene.setGamePaused(true)
        SoundManager.shared.setThrust(false)
        app.go(.levels)
    }

    func quitToMenu() {
        scene.setGamePaused(true)
        SoundManager.shared.setThrust(false)
        app.go(.menu)
    }

    // MARK: - Scene callbacks

    func updateHUD(_ state: HUDState) {
        if hud.state != state { hud.state = state }
        if state.started && showIntro { hideIntro() }
    }

    func didCrash() {
        SoundManager.shared.setThrust(false)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .crashed }
    }

    func didRunOutOfFuel() {
        SoundManager.shared.setThrust(false)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .outOfFuel }
    }

    func didWin(stars: Int, time: Double, fuelLeft: Double) {
        SoundManager.shared.setThrust(false)
        let update = app.recordWin(levelIndex: levelIndex, stars: stars, time: time)
        result = LevelResult(stars: stars, time: time, fuelLeft: fuelLeft, par: level.par, update: update)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .won }
    }
}
