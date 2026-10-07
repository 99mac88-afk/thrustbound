import CoreGraphics
import Foundation

/// Turns a level-maker grid into the LevelData the game plays.
enum LevelCompiler {
    static let cell: CGFloat = 30
    static let padWidth: CGFloat = cell * 2 - 4

    enum Problem: Equatable {
        case noStart
        case noGoal
        case startBlocked
        case goalBlocked
        case padsOverlap
    }

    /// Reasons the level can't be played yet (empty means it's playable).
    static func problems(_ e: EditorLevel) -> [Problem] {
        var list: [Problem] = []
        if let s = e.start {
            if !e.padFits(at: s) { list.append(.startBlocked) }
        } else {
            list.append(.noStart)
        }
        if let g = e.goal {
            if !e.padFits(at: g) { list.append(.goalBlocked) }
        } else {
            list.append(.noGoal)
        }
        if let s = e.start, let g = e.goal,
           !Set(EditorLevel.padCells(s)).isDisjoint(with: EditorLevel.padCells(g)) {
            list.append(.padsOverlap)
        }
        return list
    }

    /// `withTerrain: false` skips tracing the rock (the editor draws rock on its own).
    static func compile(_ e: EditorLevel, worldCount: Int = 8, title: String? = nil, withTerrain: Bool = true) -> LevelData {
        let s = cell
        let width = CGFloat(e.cols) * s
        let height = CGFloat(e.rows) * s

        func center(_ c: Int, _ r: Int) -> CGPoint {
            CGPoint(x: (CGFloat(c) + 0.5) * s, y: (CGFloat(r) + 0.5) * s)
        }
        func pad(_ cellPos: GridCell?) -> Pad {
            guard let p = cellPos else { return Pad(x: -9999, y: -9999, width: padWidth) }
            return Pad(x: CGFloat(p.c + 1) * s, y: CGFloat(p.r) * s, width: padWidth)
        }
        func free(_ c: Int, _ r: Int) -> Bool { e.inBounds(c, r) && !e.isRock(c, r) }

        var stars: [CGPoint] = []
        var cans: [CGPoint] = []
        var spikes: [[CGPoint]] = []
        var mines: [Mine] = []
        var spinners: [Spinner] = []
        var lasers: [Laser] = []
        var winds: [Wind] = []
        var keys: [KeyItem] = []
        var doors: [Door] = []

        for item in e.items where free(item.c, item.r) {
            let p = center(item.c, item.r)
            let x0 = CGFloat(item.c) * s
            let y0 = CGFloat(item.r) * s
            switch item.kind {
            case .star:
                if stars.count < 3 { stars.append(p) }
            case .fuel:
                cans.append(p)
            case .key:
                keys.append(KeyItem(position: p, color: min(max(item.color, 0), 2)))
            case .door:
                doors.append(Door(rect: CGRect(x: x0, y: y0, width: s, height: s), color: min(max(item.color, 0), 2)))
            case .mine:
                mines.append(Mine(radius: 12, path: [p], speed: 0, loop: false))
            case .movingMine:
                if let c2 = item.c2, let r2 = item.r2, free(c2, r2), c2 != item.c || r2 != item.r {
                    mines.append(Mine(radius: 12, path: [p, center(c2, r2)], speed: 90, loop: false))
                } else {
                    mines.append(Mine(radius: 12, path: [p], speed: 0, loop: false))
                }
            case .spinner:
                let length = CGFloat(min(max(item.size, 2), 4)) * s - 8
                spinners.append(Spinner(center: p, length: length, arms: 2, speed: item.dir == 1 ? -1.3 : 1.3, phase: 0))
            case .laser:
                let phase = (Double(lasers.count) * 0.7).truncatingRemainder(dividingBy: 2.8)
                if item.dir == 1 {
                    var r0 = item.r
                    var r1 = item.r
                    while free(item.c, r0 - 1) { r0 -= 1 }
                    while free(item.c, r1 + 1) { r1 += 1 }
                    lasers.append(Laser(a: CGPoint(x: p.x, y: CGFloat(r0) * s - 4),
                                        b: CGPoint(x: p.x, y: CGFloat(r1 + 1) * s + 4),
                                        on: 1.2, off: 1.6, phase: phase))
                } else {
                    var c0 = item.c
                    var c1 = item.c
                    while free(c0 - 1, item.r) { c0 -= 1 }
                    while free(c1 + 1, item.r) { c1 += 1 }
                    lasers.append(Laser(a: CGPoint(x: CGFloat(c0) * s - 4, y: p.y),
                                        b: CGPoint(x: CGFloat(c1 + 1) * s + 4, y: p.y),
                                        on: 1.2, off: 1.6, phase: phase))
                }
            case .wind:
                let force: CGPoint
                switch item.dir {
                case 1: force = CGPoint(x: 220, y: 0)
                case 2: force = CGPoint(x: 0, y: -220)
                case 3: force = CGPoint(x: -220, y: 0)
                default: force = CGPoint(x: 0, y: 220)
                }
                winds.append(Wind(rect: CGRect(x: x0, y: y0, width: s, height: s), force: force))
            case .spikes:
                let w = s / 2
                let h: CGFloat = 14
                for k in 0..<2 {
                    let o = CGFloat(k) * w
                    switch item.dir {
                    case 2:
                        let y = y0 + s
                        spikes.append([CGPoint(x: x0 + o + w, y: y), CGPoint(x: x0 + o, y: y), CGPoint(x: x0 + o + w / 2, y: y - h)])
                    case 1:
                        spikes.append([CGPoint(x: x0, y: y0 + o + w), CGPoint(x: x0, y: y0 + o), CGPoint(x: x0 + h, y: y0 + o + w / 2)])
                    case 3:
                        let x = x0 + s
                        spikes.append([CGPoint(x: x, y: y0 + o), CGPoint(x: x, y: y0 + o + w), CGPoint(x: x - h, y: y0 + o + w / 2)])
                    default:
                        spikes.append([CGPoint(x: x0 + o, y: y0), CGPoint(x: x0 + o + w, y: y0), CGPoint(x: x0 + o + w / 2, y: y0 + h)])
                    }
                }
            }
        }

        let outer = [CGPoint(x: -1000, y: -1000), CGPoint(x: width + 1000, y: -1000),
                     CGPoint(x: width + 1000, y: height + 1000), CGPoint(x: -1000, y: height + 1000)]
        let terrain: [[[CGPoint]]] = withTerrain ? [[outer] + rockOutlines(e)] : []
        let par = e.clearTime.map { max(10, ($0 * 1.2).rounded(.up)) } ?? 60

        return LevelData(
            id: 0,
            world: min(max(e.theme, 0), max(0, worldCount - 1)),
            name: title ?? e.name,
            hint: "",
            nameRu: nil,
            hintRu: nil,
            width: width,
            height: height,
            fuel: min(max(e.fuel, EditorLevel.fuelRange.lowerBound), EditorLevel.fuelRange.upperBound),
            par: par,
            start: pad(e.start),
            goal: pad(e.goal),
            terrain: terrain,
            stars: stars,
            cans: cans,
            spikes: spikes,
            mines: mines,
            spinners: spinners,
            lasers: lasers,
            winds: winds,
            keys: keys,
            doors: doors
        )
    }

    private struct GridPoint: Hashable {
        let x: Int
        let y: Int
    }

    /// Outlines between rock and open cells (outside the grid counts as rock),
    /// traced so that rock is always on the left of each edge, the same
    /// convention the built-in levels use.
    static func rockOutlines(_ e: EditorLevel) -> [[CGPoint]] {
        var outgoing: [GridPoint: [GridPoint]] = [:]
        var order: [GridPoint] = []
        func add(_ a: GridPoint, _ b: GridPoint) {
            if outgoing[a] == nil { order.append(a) }
            outgoing[a, default: []].append(b)
        }
        for r in 0..<e.rows {
            for c in 0..<e.cols where !e.isRock(c, r) {
                if e.isRock(c, r - 1) { add(GridPoint(x: c + 1, y: r), GridPoint(x: c, y: r)) }
                if e.isRock(c, r + 1) { add(GridPoint(x: c, y: r + 1), GridPoint(x: c + 1, y: r + 1)) }
                if e.isRock(c - 1, r) { add(GridPoint(x: c, y: r), GridPoint(x: c, y: r + 1)) }
                if e.isRock(c + 1, r) { add(GridPoint(x: c + 1, y: r + 1), GridPoint(x: c + 1, y: r)) }
            }
        }

        var rings: [[CGPoint]] = []
        var cursor = 0
        let limit = e.cols * e.rows * 4 + 16
        while cursor < order.count {
            let first = order[cursor]
            guard let outs = outgoing[first], !outs.isEmpty else {
                cursor += 1
                continue
            }
            var loop: [GridPoint] = [first]
            var current = first
            var steps = 0
            while steps < limit {
                steps += 1
                guard var options = outgoing[current], let next = options.popLast() else { break }
                outgoing[current] = options
                if next == first { break }
                loop.append(next)
                current = next
            }
            let simplified = dropStraightPoints(loop)
            if simplified.count >= 3 {
                rings.append(simplified.map { CGPoint(x: CGFloat($0.x) * cell, y: CGFloat($0.y) * cell) })
            }
        }
        return rings
    }

    private static func dropStraightPoints(_ loop: [GridPoint]) -> [GridPoint] {
        guard loop.count >= 3 else { return loop }
        var result: [GridPoint] = []
        let n = loop.count
        for i in 0..<n {
            let a = loop[(i + n - 1) % n]
            let b = loop[i]
            let c = loop[(i + 1) % n]
            let straight = (a.x == b.x && b.x == c.x) || (a.y == b.y && b.y == c.y)
            if !straight { result.append(b) }
        }
        return result
    }
}
