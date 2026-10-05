import CoreGraphics
import Foundation

// Small vector helpers on CGPoint so the simulation reads naturally.
extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    static func -= (a: inout CGPoint, b: CGPoint) { a = a - b }

    var length: CGFloat { (x * x + y * y).squareRoot() }
    var lengthSquared: CGFloat { x * x + y * y }

    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }

    func rotated(by angle: CGFloat) -> CGPoint {
        let c = cos(angle)
        let s = sin(angle)
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }

    var normalized: CGPoint {
        let l = length
        return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero
    }

    init(_ array: [CGFloat]) {
        self.init(x: array.count > 0 ? array[0] : 0, y: array.count > 1 ? array[1] : 0)
    }
}

enum Geo {
    @inline(__always)
    static func closestPoint(onSegment a: CGPoint, _ b: CGPoint, to p: CGPoint) -> CGPoint {
        let ab = b - a
        let len2 = ab.lengthSquared
        if len2 < 1e-9 { return a }
        let t = min(1, max(0, (p - a).dot(ab) / len2))
        return a + ab * t
    }

    @inline(__always)
    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        (p - closestPoint(onSegment: a, b, to: p)).length
    }

    /// Wraps an angle into -pi...pi.
    static func wrap(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    static func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        func sign(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = sign(p, a, b)
        let d2 = sign(p, b, c)
        let d3 = sign(p, c, a)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
