import SwiftUI

struct LevelRecord: Codable, Equatable {
    var stars: Int
    var bestTime: Double
}

struct RecordUpdate {
    let newBestStars: Bool
    let newBestTime: Bool
    let previousBestTime: Double?
    let firstClear: Bool
}

/// Options passed on the command line (used by CI to capture screenshots).
struct LaunchOptions {
    var screen: String?
    var level: Int?
    var demo = false
    var lang: Lang?

    static func parse(_ args: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        if let i = args.firstIndex(of: "-lang"), i + 1 < args.count {
            options.lang = Lang(rawValue: args[i + 1].lowercased())
        }
        guard let i = args.firstIndex(of: "-screenshot"), i + 1 < args.count else { return options }
        let parts = args[i + 1].split(separator: ":").map(String.init)
        options.screen = parts.first
        if parts.count > 1 { options.level = Int(parts[1]) }
        if parts.count > 2 { options.demo = parts[2] == "demo" }
        return options
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case menu
        case levels
        case game(Int)
        case howTo
        case settings
    }

    @Published var screen: Screen = .menu
    @Published private(set) var records: [Int: LevelRecord] = [:]
    @Published var soundOn: Bool {
        didSet {
            defaults.set(soundOn, forKey: Keys.sound)
            SoundManager.shared.enabled = soundOn
        }
    }
    @Published var hapticsOn: Bool {
        didSet {
            defaults.set(hapticsOn, forKey: Keys.haptics)
            Haptics.enabled = hapticsOn
        }
    }
    @Published var swapControls: Bool {
        didSet { defaults.set(swapControls, forKey: Keys.swap) }
    }
    @Published var unlockAll: Bool {
        didSet { defaults.set(unlockAll, forKey: Keys.unlockAll) }
    }
    /// Language picked in Settings; `.system` follows the iPhone's language.
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// The language the game is shown in right now.
    var lang: Lang { launch.lang ?? Lang.resolve(language) }
    /// All visible text in the current language.
    var s: L10n { L10n(lang) }

    let library: LevelLibrary
    let launch: LaunchOptions
    /// Bumped every time a game starts so SwiftUI builds a fresh game screen.
    private(set) var gameToken = 0

    var levels: [LevelData] { library.levels }
    var worlds: [WorldInfo] { library.worlds }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let sound = "soundOn"
        static let haptics = "hapticsOn"
        static let swap = "swapControls"
        static let unlockAll = "unlockAll"
        static let language = "language"
        static let records = "levelRecords.v1"
    }

    init() {
        let ud = UserDefaults.standard
        ud.register(defaults: [Keys.sound: true, Keys.haptics: true, Keys.swap: false, Keys.unlockAll: false,
                               Keys.language: AppLanguage.system.rawValue])
        library = LevelLibrary.load()
        launch = LaunchOptions.parse(ProcessInfo.processInfo.arguments)
        _soundOn = Published(initialValue: ud.bool(forKey: Keys.sound))
        _hapticsOn = Published(initialValue: ud.bool(forKey: Keys.haptics))
        _swapControls = Published(initialValue: ud.bool(forKey: Keys.swap))
        _unlockAll = Published(initialValue: ud.bool(forKey: Keys.unlockAll))
        _language = Published(initialValue: AppLanguage(rawValue: ud.string(forKey: Keys.language) ?? "") ?? .system)
        if let data = ud.data(forKey: Keys.records),
           let decoded = try? JSONDecoder().decode([String: LevelRecord].self, from: data) {
            var map: [Int: LevelRecord] = [:]
            for (k, v) in decoded {
                if let id = Int(k) { map[id] = v }
            }
            records = map
        }
        SoundManager.shared.enabled = soundOn
        Haptics.enabled = hapticsOn
        applyLaunchOptions()
    }

    private func applyLaunchOptions() {
        guard let screenName = launch.screen else { return }
        switch screenName {
        case "levels": screen = .levels
        case "howto": screen = .howTo
        case "settings": screen = .settings
        case "game":
            let index = max(0, min(levels.count - 1, (launch.level ?? 1) - 1))
            if !levels.isEmpty { screen = .game(index) }
        default: screen = .menu
        }
    }

    // MARK: - Navigation

    func go(_ newScreen: Screen) {
        if case .game = newScreen { gameToken += 1 }
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = newScreen
        }
    }

    func world(for level: LevelData) -> WorldInfo? {
        worlds.indices.contains(level.world) ? worlds[level.world] : nil
    }

    func worldIndices() -> [Int] {
        Array(Set(levels.map { $0.world })).sorted()
    }

    func levelIndices(inWorld world: Int) -> [Int] {
        levels.indices.filter { levels[$0].world == world }
    }

    // MARK: - Progress

    func record(forIndex index: Int) -> LevelRecord? {
        guard levels.indices.contains(index) else { return nil }
        return records[levels[index].id]
    }

    func isUnlocked(_ index: Int) -> Bool {
        guard levels.indices.contains(index) else { return false }
        if unlockAll || index == 0 || launch.screen != nil { return true }
        if records[levels[index].id] != nil { return true }
        return records[levels[index - 1].id] != nil
    }

    var totalStars: Int { records.values.reduce(0) { $0 + $1.stars } }
    var maxStars: Int { levels.count * 3 }
    var completedCount: Int { records.count }

    func stars(inWorld world: Int) -> Int {
        levelIndices(inWorld: world).reduce(0) { $0 + (record(forIndex: $1)?.stars ?? 0) }
    }

    /// The level the Play button should open.
    var continueIndex: Int {
        for i in levels.indices where record(forIndex: i) == nil && isUnlocked(i) {
            return i
        }
        return max(0, levels.count - 1)
    }

    var hasProgress: Bool { !records.isEmpty }

    @discardableResult
    func recordWin(levelIndex: Int, stars: Int, time: Double) -> RecordUpdate {
        guard levels.indices.contains(levelIndex) else {
            return RecordUpdate(newBestStars: false, newBestTime: false, previousBestTime: nil, firstClear: false)
        }
        let id = levels[levelIndex].id
        let old = records[id]
        var rec = old ?? LevelRecord(stars: stars, bestTime: time)
        let newStars = old == nil || stars > rec.stars
        let newTime = old == nil || time < rec.bestTime
        if newStars { rec.stars = stars }
        if newTime { rec.bestTime = time }
        records[id] = rec
        saveRecords()
        return RecordUpdate(newBestStars: newStars && old != nil, newBestTime: newTime && old != nil,
                            previousBestTime: old?.bestTime, firstClear: old == nil)
    }

    func resetProgress() {
        records = [:]
        saveRecords()
    }

    private func saveRecords() {
        var encoded: [String: LevelRecord] = [:]
        for (k, v) in records { encoded[String(k)] = v }
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Keys.records)
        }
    }
}
