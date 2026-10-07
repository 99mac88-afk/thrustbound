import Foundation

/// The player's own levels, saved as JSON files in the app's Documents folder.
@MainActor
final class LevelStore: ObservableObject {
    @Published private(set) var levels: [EditorLevel] = []

    /// The editor that is open (kept alive while a level is being test-played).
    private(set) var session: EditorSession?

    let worlds: [WorldInfo]
    private let folder: URL

    init(worlds: [WorldInfo], folder: URL? = nil) {
        self.worlds = worlds
        let base = folder ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyLevels", isDirectory: true)
        self.folder = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [EditorLevel] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let level = try? decoder.decode(EditorLevel.self, from: data) {
                found.append(level)
            }
        }
        levels = sorted(found)
    }

    private func sorted(_ list: [EditorLevel]) -> [EditorLevel] {
        list.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    func level(_ id: UUID) -> EditorLevel? {
        levels.first { $0.id == id }
    }

    // MARK: - Changes

    func save(_ level: EditorLevel) {
        var copy = level
        copy.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(copy) {
            try? data.write(to: url(for: copy.id), options: .atomic)
        }
        if let i = levels.firstIndex(where: { $0.id == copy.id }) {
            levels[i] = copy
        } else {
            levels.append(copy)
        }
        levels = sorted(levels)
    }

    func create(name: String, theme: Int) -> EditorLevel {
        var level = EditorLevel(name: name, theme: theme)
        // A ready-to-fly starter: start pad on the left, goal on the right.
        level.start = GridCell(c: 2, r: 1)
        level.goal = GridCell(c: level.cols - 4, r: 1)
        save(level)
        return level
    }

    nonisolated static let sampleName = "Example Cave"

    /// A small finished level that shows off most tools.
    func addSample(theme: Int) -> EditorLevel {
        let level = LevelStore.sample(theme: theme)
        save(level)
        return level
    }

    nonisolated static func sample(theme: Int) -> EditorLevel {
        var l = EditorLevel(name: sampleName, cols: EditorLevel.narrowCols, rows: 30, theme: theme)
        func rock(_ c0: Int, _ c1: Int, _ r: Int) {
            for c in c0...c1 { l.setRock(c, r, true) }
        }
        rock(0, 8, 8)
        rock(0, 8, 9)
        rock(5, 13, 16)
        rock(5, 13, 17)
        rock(8, 13, 25)
        rock(0, 1, 20)
        rock(12, 13, 20)
        l.start = GridCell(c: 1, r: 1)
        l.goal = GridCell(c: 10, r: 26)
        l.fuel = 30
        l.items = [
            EditorItem(kind: .spikes, c: 5, r: 1),
            EditorItem(kind: .spikes, c: 6, r: 1),
            EditorItem(kind: .spikes, c: 7, r: 1),
            EditorItem(kind: .star, c: 11, r: 4),
            EditorItem(kind: .fuel, c: 2, r: 12),
            EditorItem(kind: .movingMine, c: 6, r: 12, c2: 12, r2: 12),
            EditorItem(kind: .wind, c: 11, r: 10),
            EditorItem(kind: .wind, c: 12, r: 10),
            EditorItem(kind: .star, c: 2, r: 18),
            EditorItem(kind: .laser, c: 6, r: 21),
            EditorItem(kind: .spinner, c: 4, r: 24, size: 2),
            EditorItem(kind: .star, c: 1, r: 27)
        ]
        return l
    }

    func duplicate(_ id: UUID, suffix: String) -> EditorLevel? {
        guard var copy = level(id) else { return nil }
        copy.id = UUID()
        copy.name = String((copy.name + suffix).prefix(40))
        copy.publishedID = nil
        copy.publishedHash = nil
        save(copy)
        return copy
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        levels.removeAll { $0.id == id }
        if session?.level.id == id { session = nil }
    }

    /// Called when the author lands on their own level during a test flight.
    func recordClear(id: UUID, hash: String, time: Double) {
        if let s = session, s.level.id == id {
            s.recordClear(hash: hash, time: time)
            save(s.level)
            return
        }
        guard var level = level(id), level.contentHash == hash else { return }
        level.markCleared(hash: hash, time: time)
        save(level)
    }

    func markPublished(id: UUID, remoteID: String, hash: String) {
        if let s = session, s.level.id == id {
            s.level.publishedID = remoteID
            s.level.publishedHash = hash
            save(s.level)
            return
        }
        guard var level = level(id) else { return }
        level.publishedID = remoteID
        level.publishedHash = hash
        save(level)
    }

    // MARK: - Editor sessions

    func openSession(_ id: UUID) -> EditorSession? {
        if let s = session, s.level.id == id { return s }
        guard let level = level(id) else { return nil }
        let s = EditorSession(level: level, store: self)
        session = s
        return s
    }

    func closeSession() {
        if let s = session { save(s.level) }
        session = nil
    }
}

extension EditorLevel {
    mutating func markCleared(hash: String, time: Double) {
        guard contentHash == hash else { return }
        if clearedHash == hash, let best = clearTime {
            clearTime = min(best, time)
        } else {
            clearTime = time
        }
        clearedHash = hash
    }

    var isPublishedAsIs: Bool { publishedID != nil && publishedHash == contentHash }
}
