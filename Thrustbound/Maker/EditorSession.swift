import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case rock
    case erase
    case hand
    case start
    case goal
    case star
    case fuel
    case spikes
    case mine
    case movingMine
    case spinner
    case laser
    case wind
    case key
    case door

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rock: return "square.fill"
        case .erase: return "eraser.fill"
        case .hand: return "hand.draw.fill"
        case .start: return "airplane.departure"
        case .goal: return "flag.checkered"
        case .star: return "star.fill"
        case .fuel: return "fuelpump.fill"
        case .spikes: return "triangle.fill"
        case .mine: return "circle.hexagongrid.fill"
        case .movingMine: return "arrow.left.and.right.circle.fill"
        case .spinner: return "fanblades.fill"
        case .laser: return "line.diagonal"
        case .wind: return "wind"
        case .key: return "key.fill"
        case .door: return "door.left.hand.closed"
        }
    }

    /// Rock and erase paint while dragging; everything else is placed where the finger lifts.
    var paints: Bool { self == .rock || self == .erase }

    var itemKind: ItemKind? {
        switch self {
        case .star: return .star
        case .fuel: return .fuel
        case .spikes: return .spikes
        case .mine: return .mine
        case .movingMine: return .movingMine
        case .spinner: return .spinner
        case .laser: return .laser
        case .wind: return .wind
        case .key: return .key
        case .door: return .door
        default: return nil
        }
    }
}

/// One open level in the editor: the level being edited, the chosen tool and undo history.
@MainActor
final class EditorSession: ObservableObject {
    @Published var level: EditorLevel
    @Published var tool: EditorTool = .rock {
        didSet { if tool != .movingMine { pendingMine = nil } }
    }
    @Published var windDir = 0
    @Published var color = 0
    @Published var laserDir = 0
    @Published var spinnerSize = 3
    @Published var spinnerDir = 0
    /// Index of a moving mine waiting for the end of its track.
    @Published private(set) var pendingMine: Int?
    /// A short message for the player (e.g. "3 stars max").
    @Published var notice: EditorNotice?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let scene: EditorScene
    /// World themes the level can use (from levels.json).
    let worlds: [WorldInfo]
    /// Text drawn inside the canvas (the LAND label on the goal pad).
    var strings = L10n(.en) {
        didSet { if strings.lang != oldValue.lang { scene.redrawAll() } }
    }
    var worldCount: Int { max(1, worlds.count) }
    func worldInfo(_ index: Int) -> WorldInfo? { worlds.indices.contains(index) ? worlds[index] : nil }

    private weak var store: LevelStore?
    private var undoStack: [EditorLevel] = []
    private var redoStack: [EditorLevel] = []
    private var strokeStart: EditorLevel?
    private var lastPainted: GridCell?
    private static let undoLimit = 80

    init(level: EditorLevel, store: LevelStore) {
        self.level = level
        self.store = store
        worlds = store.worlds
        scene = EditorScene(size: CGSize(width: 390, height: 600))
        scene.session = self
    }

    // MARK: - Strokes (called by the scene)

    func beginStroke() {
        strokeStart = level
        lastPainted = nil
    }

    /// Paint tools: called for every cell the finger crosses.
    func paint(_ cell: GridCell) {
        guard tool.paints, cell != lastPainted, level.inBounds(cell.c, cell.r) else { return }
        lastPainted = cell
        var l = level
        switch tool {
        case .rock:
            guard !l.isPadCell(cell) else { return }
            l.items.removeAll { $0.c == cell.c && $0.r == cell.r }
            l.setRock(cell.c, cell.r, true)
        case .erase:
            l.items.removeAll { $0.c == cell.c && $0.r == cell.r }
            l.setRock(cell.c, cell.r, false)
        default:
            return
        }
        if l.rock != level.rock || l.items != level.items { level = l }
    }

    /// Placement tools: called once where the finger lifts.
    func place(_ cell: GridCell) {
        guard level.inBounds(cell.c, cell.r) else { return }
        switch tool {
        case .rock, .erase, .hand:
            return
        case .start, .goal:
            placePad(near: cell, goal: tool == .goal)
        default:
            placeItem(at: cell)
        }
    }

    func endStroke() {
        defer {
            strokeStart = nil
            lastPainted = nil
        }
        guard let before = strokeStart, before != level else { return }
        undoStack.append(before)
        if undoStack.count > EditorSession.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshUndo()
        save()
    }

    /// A second finger arrived: forget what this touch did.
    func cancelStroke() {
        if let before = strokeStart { level = before }
        strokeStart = nil
        lastPainted = nil
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(level)
        level = keepingBookkeeping(previous)
        pendingMine = nil
        refreshUndo()
        save()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(level)
        level = keepingBookkeeping(next)
        pendingMine = nil
        refreshUndo()
        save()
    }

    /// Clear/publish state belongs to "now", not to the snapshot.
    private func keepingBookkeeping(_ snapshot: EditorLevel) -> EditorLevel {
        var l = snapshot
        l.clearedHash = level.clearedHash
        l.clearTime = level.clearTime
        l.publishedID = level.publishedID
        l.publishedHash = level.publishedHash
        l.name = level.name
        return l
    }

    private func refreshUndo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Changes from the settings sheet (size, fuel, theme) are undoable as one step.
    func edit(_ change: (inout EditorLevel) -> Void) {
        var l = level
        change(&l)
        guard l != level else { return }
        undoStack.append(level)
        if undoStack.count > EditorSession.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        level = l
        pendingMine = nil
        refreshUndo()
        save()
    }

    func rename(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty, trimmed != level.name else { return }
        level.name = trimmed
        save()
    }

    func save() {
        store?.save(level)
    }

    func recordClear(hash: String, time: Double) {
        level.markCleared(hash: hash, time: time)
    }

    // MARK: - Placing things

    private func placePad(near cell: GridCell, goal: Bool) {
        let other = goal ? level.start : level.goal
        let candidates = [cell, GridCell(c: cell.c, r: cell.r + 1), GridCell(c: cell.c - 1, r: cell.r),
                          GridCell(c: cell.c - 1, r: cell.r + 1), GridCell(c: cell.c, r: cell.r - 1),
                          GridCell(c: cell.c - 1, r: cell.r - 1)]
        func overlapsOther(_ p: GridCell) -> Bool {
            guard let o = other else { return false }
            return !Set(EditorLevel.padCells(p)).isDisjoint(with: EditorLevel.padCells(o))
        }
        guard let spot = candidates.first(where: { level.padFits(at: $0) && !overlapsOther($0) }) else {
            notice = .padNeedsFloor
            Haptics.failure()
            return
        }
        var l = level
        let cells = EditorLevel.padCells(spot)
        l.items.removeAll { item in cells.contains(item.cell) }
        if goal { l.goal = spot } else { l.start = spot }
        level = l
        pendingMine = nil
        Haptics.light()
    }

    private func placeItem(at cell: GridCell) {
        guard let kind = tool.itemKind else { return }
        if level.isRock(cell.c, cell.r) || level.isPadCell(cell) {
            notice = .cellTaken
            Haptics.failure()
            return
        }

        // Second tap of a moving mine: the end of its track.
        if kind == .movingMine, let index = pendingMine, level.items.indices.contains(index),
           level.items[index].kind == .movingMine {
            var l = level
            if l.items[index].cell != cell {
                l.items[index].c2 = cell.c
                l.items[index].r2 = cell.r
            }
            level = l
            pendingMine = nil
            Haptics.light()
            return
        }

        var l = level
        if let existing = l.item(at: cell) {
            // Tapping a thing of the same kind turns or recolours it.
            if l.items[existing].kind == kind {
                switch kind {
                case .spikes, .wind:
                    l.items[existing].dir = (l.items[existing].dir + 1) % 4
                    if kind == .wind { windDir = l.items[existing].dir }
                case .laser:
                    l.items[existing].dir = l.items[existing].dir == 1 ? 0 : 1
                    laserDir = l.items[existing].dir
                case .spinner:
                    l.items[existing].dir = l.items[existing].dir == 1 ? 0 : 1
                    l.items[existing].size = spinnerSize
                    spinnerDir = l.items[existing].dir
                case .key, .door:
                    l.items[existing].color = (l.items[existing].color + 1) % 3
                    color = l.items[existing].color
                case .movingMine:
                    pendingMine = existing
                    notice = .mineTrack
                    level = l
                    return
                default:
                    break
                }
                level = l
                Haptics.light()
                return
            }
            l.items.remove(at: existing)
        }
        if kind == .star && l.items.filter({ $0.kind == .star }).count >= 3 {
            notice = .starLimit
            Haptics.failure()
            return
        }
        guard l.items.count < EditorLevel.maxItems else {
            notice = .itemLimit
            Haptics.failure()
            return
        }

        var item = EditorItem(kind: kind, c: cell.c, r: cell.r)
        switch kind {
        case .spikes: item.dir = spikeDirection(at: cell, in: l)
        case .wind: item.dir = windDir
        case .laser: item.dir = laserDir
        case .spinner:
            item.dir = spinnerDir
            item.size = spinnerSize
        case .key, .door: item.color = color
        default: break
        }
        l.items.append(item)
        level = l
        if kind == .movingMine {
            pendingMine = l.items.count - 1
            notice = .mineTrack
        } else {
            pendingMine = nil
        }
        Haptics.light()
    }

    /// Spikes stick to the nearest rock: floor first, then ceiling, then walls.
    private func spikeDirection(at cell: GridCell, in l: EditorLevel) -> Int {
        if l.isRock(cell.c, cell.r - 1) { return 0 }
        if l.isRock(cell.c, cell.r + 1) { return 2 }
        if l.isRock(cell.c - 1, cell.r) { return 1 }
        if l.isRock(cell.c + 1, cell.r) { return 3 }
        return 0
    }

    // MARK: - Checks

    var problems: [LevelCompiler.Problem] { LevelCompiler.problems(level) }
}

enum EditorNotice: Equatable {
    case padNeedsFloor
    case cellTaken
    case starLimit
    case itemLimit
    case mineTrack
}
