import CryptoKit
import Foundation

/// A grid square in the level maker. Row 0 is the bottom row.
struct GridCell: Codable, Hashable {
    var c: Int
    var r: Int
}

enum ItemKind: String, Codable, CaseIterable {
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
}

/// Something placed in a grid cell.
struct EditorItem: Codable, Hashable {
    var kind: ItemKind
    var c: Int
    var r: Int
    /// spikes / wind: 0 up, 1 right, 2 down, 3 left. laser: 0 across, 1 up-down. spinner: 0 anticlockwise, 1 clockwise.
    var dir: Int = 0
    /// key / door colour 0...2
    var color: Int = 0
    /// spinner arm length in cells 2...4
    var size: Int = 3
    /// moving mine: the other end of its track
    var c2: Int?
    var r2: Int?

    init(kind: ItemKind, c: Int, r: Int, dir: Int = 0, color: Int = 0, size: Int = 3, c2: Int? = nil, r2: Int? = nil) {
        self.kind = kind
        self.c = c
        self.r = r
        self.dir = dir
        self.color = color
        self.size = size
        self.c2 = c2
        self.r2 = r2
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        kind = try k.decode(ItemKind.self, forKey: .kind)
        c = try k.decode(Int.self, forKey: .c)
        r = try k.decode(Int.self, forKey: .r)
        dir = try k.decodeIfPresent(Int.self, forKey: .dir) ?? 0
        color = try k.decodeIfPresent(Int.self, forKey: .color) ?? 0
        size = try k.decodeIfPresent(Int.self, forKey: .size) ?? 3
        c2 = try k.decodeIfPresent(Int.self, forKey: .c2)
        r2 = try k.decodeIfPresent(Int.self, forKey: .r2)
    }

    var cell: GridCell { GridCell(c: c, r: r) }
}

/// A level made in the level maker. This is also the format published online.
struct EditorLevel: Codable, Identifiable, Equatable {
    static let narrowCols = 14
    static let wideCols = 28
    static let minRows = 20
    static let maxRows = 120
    static let maxItems = 160
    static let fuelRange: ClosedRange<Double> = 5...90

    var id: UUID
    var version: Int = 1
    var name: String
    var cols: Int
    var rows: Int
    /// Rock cells, row-major from the bottom row; 1 = rock.
    var rock: [UInt8]
    var fuel: Double
    var theme: Int
    var start: GridCell?
    var goal: GridCell?
    var items: [EditorItem]
    /// The author's best landing time on this exact layout (used as par).
    var clearTime: Double?

    // Local bookkeeping, never published.
    var updatedAt: Date?
    var clearedHash: String?
    var publishedID: String?
    var publishedHash: String?

    enum CodingKeys: String, CodingKey {
        case id, version, name, cols, rows, rock, fuel, theme, start, goal, items, clearTime
        case updatedAt, clearedHash, publishedID, publishedHash
    }

    init(name: String, cols: Int = EditorLevel.narrowCols, rows: Int = 40, theme: Int = 0) {
        id = UUID()
        self.name = name
        self.cols = cols
        self.rows = rows
        rock = [UInt8](repeating: 0, count: cols * rows)
        fuel = 25
        self.theme = theme
        items = []
        // A floor to land on.
        for c in 0..<cols { rock[c] = 1 }
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        version = try k.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try k.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        let rawCols = try k.decode(Int.self, forKey: .cols)
        let rawRows = try k.decode(Int.self, forKey: .rows)
        cols = rawCols == EditorLevel.wideCols ? EditorLevel.wideCols : EditorLevel.narrowCols
        rows = min(max(rawRows, EditorLevel.minRows), EditorLevel.maxRows)
        let text = try k.decodeIfPresent(String.self, forKey: .rock) ?? ""
        var cells = [UInt8](repeating: 0, count: cols * rows)
        // Only trust the text if it was written for this grid size.
        if rawCols == cols && rawRows == rows && text.utf8.count == cols * rows {
            for (i, ch) in text.utf8.enumerated() where ch == UInt8(ascii: "1") {
                cells[i] = 1
            }
        }
        rock = cells
        let rawFuel = try k.decodeIfPresent(Double.self, forKey: .fuel) ?? 25
        fuel = min(max(rawFuel, EditorLevel.fuelRange.lowerBound), EditorLevel.fuelRange.upperBound)
        theme = try k.decodeIfPresent(Int.self, forKey: .theme) ?? 0
        start = try k.decodeIfPresent(GridCell.self, forKey: .start)
        goal = try k.decodeIfPresent(GridCell.self, forKey: .goal)
        let rawItems = try k.decodeIfPresent([EditorItem].self, forKey: .items) ?? []
        items = Array(rawItems.prefix(EditorLevel.maxItems))
        clearTime = try k.decodeIfPresent(Double.self, forKey: .clearTime)
        updatedAt = try k.decodeIfPresent(Date.self, forKey: .updatedAt)
        clearedHash = try k.decodeIfPresent(String.self, forKey: .clearedHash)
        publishedID = try k.decodeIfPresent(String.self, forKey: .publishedID)
        publishedHash = try k.decodeIfPresent(String.self, forKey: .publishedHash)
    }

    func encode(to encoder: Encoder) throws {
        var k = encoder.container(keyedBy: CodingKeys.self)
        try k.encode(id, forKey: .id)
        try k.encode(version, forKey: .version)
        try k.encode(name, forKey: .name)
        try k.encode(cols, forKey: .cols)
        try k.encode(rows, forKey: .rows)
        try k.encode(String(decoding: rock.map { $0 == 1 ? UInt8(ascii: "1") : UInt8(ascii: "0") }, as: UTF8.self),
                     forKey: .rock)
        try k.encode(fuel, forKey: .fuel)
        try k.encode(theme, forKey: .theme)
        try k.encodeIfPresent(start, forKey: .start)
        try k.encodeIfPresent(goal, forKey: .goal)
        try k.encode(items, forKey: .items)
        try k.encodeIfPresent(clearTime, forKey: .clearTime)
        try k.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try k.encodeIfPresent(clearedHash, forKey: .clearedHash)
        try k.encodeIfPresent(publishedID, forKey: .publishedID)
        try k.encodeIfPresent(publishedHash, forKey: .publishedHash)
    }

    // MARK: - Grid access

    func inBounds(_ c: Int, _ r: Int) -> Bool {
        c >= 0 && c < cols && r >= 0 && r < rows
    }

    /// Outside the grid counts as rock.
    func isRock(_ c: Int, _ r: Int) -> Bool {
        guard inBounds(c, r) else { return true }
        return rock[r * cols + c] == 1
    }

    mutating func setRock(_ c: Int, _ r: Int, _ value: Bool) {
        guard inBounds(c, r) else { return }
        rock[r * cols + c] = value ? 1 : 0
    }

    func item(at cell: GridCell) -> Int? {
        items.firstIndex { $0.c == cell.c && $0.r == cell.r }
    }

    /// The four cells a pad and its landing space use.
    static func padCells(_ cell: GridCell) -> [GridCell] {
        [cell, GridCell(c: cell.c + 1, r: cell.r), GridCell(c: cell.c, r: cell.r + 1), GridCell(c: cell.c + 1, r: cell.r + 1)]
    }

    /// Pads sit on two cells of rock and need two clear cells above.
    func padFits(at cell: GridCell) -> Bool {
        guard inBounds(cell.c, cell.r), inBounds(cell.c + 1, cell.r + 1) else { return false }
        guard isRock(cell.c, cell.r - 1), isRock(cell.c + 1, cell.r - 1), cell.r >= 1 else { return false }
        return EditorLevel.padCells(cell).allSatisfy { !isRock($0.c, $0.r) }
    }

    func isPadCell(_ cell: GridCell) -> Bool {
        for pad in [start, goal].compactMap({ $0 }) where EditorLevel.padCells(pad).contains(cell) {
            return true
        }
        return false
    }

    /// Resize the grid, keeping everything that still fits (anchored at the bottom-left).
    mutating func resize(cols newCols: Int, rows newRows: Int) {
        let nc = newCols == EditorLevel.wideCols ? EditorLevel.wideCols : EditorLevel.narrowCols
        let nr = min(max(newRows, EditorLevel.minRows), EditorLevel.maxRows)
        var cells = [UInt8](repeating: 0, count: nc * nr)
        for r in 0..<min(rows, nr) {
            for c in 0..<min(cols, nc) {
                cells[r * nc + c] = rock[r * cols + c]
            }
        }
        cols = nc
        rows = nr
        rock = cells
        func fits(_ c: Int, _ r: Int) -> Bool { c >= 0 && c < nc && r >= 0 && r < nr }
        items = items.filter { fits($0.c, $0.r) && ($0.c2 == nil || fits($0.c2 ?? 0, $0.r2 ?? 0)) }
        if let s = start, !fits(s.c + 1, s.r + 1) { start = nil }
        if let g = goal, !fits(g.c + 1, g.r + 1) { goal = nil }
    }

    // MARK: - Fingerprint

    /// Changes whenever anything that affects play changes. A level counts as
    /// "cleared" only while this matches the hash recorded at the author's landing.
    var contentHash: String {
        var text = "v\(version);\(cols)x\(rows);fuel=\(Int(fuel * 10));"
        text += String(decoding: rock.map { $0 == 1 ? UInt8(ascii: "1") : UInt8(ascii: "0") }, as: UTF8.self)
        text += ";s=\(start.map { "\($0.c),\($0.r)" } ?? "-");g=\(goal.map { "\($0.c),\($0.r)" } ?? "-");"
        for i in items {
            text += "\(i.kind.rawValue):\(i.c),\(i.r),\(i.dir),\(i.color),\(i.size),\(i.c2 ?? -1),\(i.r2 ?? -1);"
        }
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var isCleared: Bool { clearedHash == contentHash }

    /// The copy that gets uploaded: no local bookkeeping.
    var publishable: EditorLevel {
        var copy = self
        copy.updatedAt = nil
        copy.clearedHash = nil
        copy.publishedID = nil
        copy.publishedHash = nil
        return copy
    }
}
