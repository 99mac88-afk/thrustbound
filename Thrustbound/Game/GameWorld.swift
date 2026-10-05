import CoreGraphics
import Foundation

/// Tuning constants. Distances are points, time is seconds.
enum Physics {
    static let gravity: CGFloat = 160
    static let thrust: CGFloat = 400
    static let drag: CGFloat = 0.3
    static let maxSpeed: CGFloat = 480
    static let turnRate: CGFloat = 6.5          // radians per second
    static let crashSpeed: CGFloat = 130        // impact speed that destroys the rocket
    static let landMaxTilt: CGFloat = 0.30      // radians (~17 degrees)
    static let landMaxSpeed: CGFloat = 30
    static let landHoldTime: Double = 0.6
    static let restitution: CGFloat = 0.25
    static let friction: CGFloat = 5
    static let step: Double = 1.0 / 240.0
    static let canFuel: Double = 10
    static let pickupRadius: CGFloat = 26
    static let hazardForgiveness: CGFloat = 1.5
    static let lowFuelFraction: Double = 0.2
}

struct HullCircle {
    let offset: CGPoint
    let radius: CGFloat
}

enum RocketShape {
    /// Collision circles in rocket space (nose points to +y).
    static let hull: [HullCircle] = [
        HullCircle(offset: CGPoint(x: 0, y: 12), radius: 6),
        HullCircle(offset: CGPoint(x: 0, y: 0), radius: 8),
        HullCircle(offset: CGPoint(x: 0, y: -10), radius: 8),
        HullCircle(offset: CGPoint(x: -10, y: -17), radius: 3),
        HullCircle(offset: CGPoint(x: 10, y: -17), radius: 3)
    ]
    /// Circles that count as "feet" for landing.
    static let feet = [2, 3, 4]
    /// Height of the rocket's centre above a pad when it is resting on it.
    static let spawnHeight: CGFloat = 20
}

struct ControlInput {
    var thrust = false
    /// Direction the pilot wants the nose to point (radians, 0 = up, CCW positive).
    var targetAngle: CGFloat?
}

enum CrashCause {
    case impact
    case hazard
    case outOfBounds
}

enum GameEvent {
    case star(Int)
    case fuelCan(Int)
    case key(Int)
    case doorOpened(Int)
    case crashed(at: CGPoint, cause: CrashCause)
    case landed
    case outOfFuel
    case bump(CGFloat)
    case lowFuel
}

enum LaserState {
    case on
    case off
    case warning
}

private struct Segment {
    let a: CGPoint
    let b: CGPoint
    let normal: CGPoint
    let door: Int           // -1 for rock
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat

    init(_ a: CGPoint, _ b: CGPoint, door: Int = -1) {
        self.a = a
        self.b = b
        let d = b - a
        // Solid is on the left of each edge, so the free side is on the right.
        self.normal = CGPoint(x: d.y, y: -d.x).normalized
        self.door = door
        minX = min(a.x, b.x); maxX = max(a.x, b.x)
        minY = min(a.y, b.y); maxY = max(a.y, b.y)
    }
}

private struct MineTrack {
    let points: [CGPoint]       // includes the closing point for loops
    let cumulative: [CGFloat]
    let total: CGFloat
    let loop: Bool
    let speed: CGFloat

    init(_ mine: Mine) {
        var pts = mine.path
        if pts.isEmpty { pts = [.zero] }
        if mine.loop && pts.count > 1 { pts.append(pts[0]) }
        var cum: [CGFloat] = [0]
        for i in 1..<max(1, pts.count) {
            cum.append(cum[i - 1] + (pts[i] - pts[i - 1]).length)
        }
        points = pts
        cumulative = cum
        total = cum.last ?? 0
        loop = mine.loop
        speed = mine.speed
    }

    func position(at time: Double) -> CGPoint {
        guard points.count > 1, total > 0, speed > 0 else { return points[0] }
        var d = CGFloat(time) * speed
        if loop {
            d = d.truncatingRemainder(dividingBy: total)
        } else {
            let period = 2 * total
            d = d.truncatingRemainder(dividingBy: period)
            if d > total { d = period - d }
        }
        for k in 1..<points.count where d <= cumulative[k] {
            let segLen = cumulative[k] - cumulative[k - 1]
            let u = segLen > 0 ? (d - cumulative[k - 1]) / segLen : 0
            return points[k - 1] + (points[k] - points[k - 1]) * u
        }
        return points[points.count - 1]
    }
}

/// Pure game simulation: rocket physics, collisions, hazards and pickups.
/// Has no SpriteKit dependency so it can be unit tested.
final class GameWorld {
    enum Status {
        case flying
        case crashed
        case landed
        case outOfFuel
    }

    let level: LevelData
    private(set) var status: Status = .flying
    var position: CGPoint = .zero
    var velocity: CGPoint = .zero
    var angle: CGFloat = 0
    var fuel: Double = 0
    private(set) var time: Double = 0
    private(set) var flightTime: Double = 0
    private(set) var started = false
    private(set) var thrusting = false
    private(set) var collectedStars = Set<Int>()
    private(set) var collectedCans = Set<Int>()
    private(set) var collectedKeys = Set<Int>()
    private(set) var openDoors = Set<Int>()
    private(set) var landingTimer: Double = 0
    private(set) var touchingGoal = false
    private(set) var tiltedOnGoal = false
    private var stuckTimer: Double = 0
    private var lowFuelWarned = false
    private var events: [GameEvent] = []

    private var segments: [Segment] = []
    private let mineTracks: [MineTrack]
    private let spikeBoxes: [CGRect]

    var landingProgress: Double { min(1, landingTimer / Physics.landHoldTime) }
    var fuelFraction: Double { level.fuel > 0 ? fuel / level.fuel : 0 }
    var heldKeyColors: [Int] { collectedKeys.sorted().map { level.keys[$0].color } }

    init(level: LevelData) {
        self.level = level
        mineTracks = level.mines.map { MineTrack($0) }
        spikeBoxes = level.spikes.map { Geo.bounds(of: $0) }
        buildSegments()
        reset()
    }

    private func buildSegments() {
        var segs: [Segment] = []
        for polygon in level.terrain {
            for ring in polygon where ring.count >= 3 {
                for i in 0..<ring.count {
                    let a = ring[i]
                    let b = ring[(i + 1) % ring.count]
                    if (b - a).lengthSquared > 1e-6 {
                        segs.append(Segment(a, b))
                    }
                }
            }
        }
        for (index, door) in level.doors.enumerated() {
            let r = door.rect
            let corners = [
                CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)
            ]
            for i in 0..<4 {
                segs.append(Segment(corners[i], corners[(i + 1) % 4], door: index))
            }
        }
        segments = segs
    }

    func reset() {
        status = .flying
        position = CGPoint(x: level.start.x, y: level.start.y + RocketShape.spawnHeight)
        velocity = .zero
        angle = 0
        fuel = level.fuel
        time = 0
        flightTime = 0
        started = false
        thrusting = false
        collectedStars.removeAll()
        collectedCans.removeAll()
        collectedKeys.removeAll()
        openDoors.removeAll()
        landingTimer = 0
        touchingGoal = false
        tiltedOnGoal = false
        stuckTimer = 0
        lowFuelWarned = false
        events.removeAll()
    }

    func drainEvents() -> [GameEvent] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }

    // MARK: - Hazard state (shared with rendering)

    func minePosition(_ index: Int) -> CGPoint {
        mineTracks[index].position(at: time)
    }

    func spinnerAngle(_ index: Int) -> CGFloat {
        let s = level.spinners[index]
        return s.phase + s.speed * CGFloat(time)
    }

    func laserState(_ index: Int) -> LaserState {
        let l = level.lasers[index]
        if l.off <= 0 { return .on }
        if l.on <= 0 { return .off }
        let cycle = l.on + l.off
        var local = (time + l.phase).truncatingRemainder(dividingBy: cycle)
        if local < 0 { local += cycle }
        if local < l.on { return .on }
        if local > cycle - 0.5 { return .warning }
        return .off
    }

    // MARK: - Simulation

    func step(_ dt: Double, input: ControlInput) {
        time += dt
        guard status == .flying else {
            thrusting = false
            return
        }
        let dtf = CGFloat(dt)

        if !started && (input.thrust || input.targetAngle != nil) {
            started = true
        }
        if started { flightTime += dt }

        if let target = input.targetAngle {
            let diff = Geo.wrap(target - angle)
            let maxStep = Physics.turnRate * dtf
            angle = Geo.wrap(angle + max(-maxStep, min(maxStep, diff)))
        }

        var accel = CGPoint(x: 0, y: -Physics.gravity)
        thrusting = input.thrust && fuel > 0
        if thrusting {
            accel += CGPoint(x: -sin(angle), y: cos(angle)) * Physics.thrust
            fuel = max(0, fuel - dt)
        }
        for wind in level.winds where wind.rect.contains(position) {
            accel += wind.force
        }
        velocity += accel * dtf
        velocity = velocity * max(0, 1 - Physics.drag * dtf)
        let speed = velocity.length
        if speed > Physics.maxSpeed {
            velocity = velocity * (Physics.maxSpeed / speed)
        }
        position += velocity * dtf

        resolveTerrain(dtf)
        guard status == .flying else { return }
        checkHazards()
        guard status == .flying else { return }
        collectItems()
        updateLanding(dt)
        guard status == .flying else { return }
        updateFuel(dt)

        if position.x < -40 || position.x > level.width + 40 || position.y < -40 || position.y > level.height + 40 {
            crash(at: position, cause: .outOfBounds)
        }
    }

    private func resolveTerrain(_ dt: CGFloat) {
        var worstImpact: CGFloat = 0
        var impactPoint = position
        for circle in RocketShape.hull {
            var center = position + circle.offset.rotated(by: angle)
            let r = circle.radius
            for seg in segments {
                if seg.door >= 0 && openDoors.contains(seg.door) { continue }
                if center.x + r < seg.minX || center.x - r > seg.maxX ||
                    center.y + r < seg.minY || center.y - r > seg.maxY { continue }
                let q = Geo.closestPoint(onSegment: seg.a, seg.b, to: center)
                let d = center - q
                let dist2 = d.lengthSquared
                if dist2 >= r * r { continue }
                let dist = dist2.squareRoot()
                let n = dist > 1e-5 ? d * (1 / dist) : seg.normal
                let push = r - dist
                position += n * push
                center += n * push
                let vn = velocity.dot(n)
                if vn < 0 {
                    let impact = -vn
                    if impact > worstImpact {
                        worstImpact = impact
                        impactPoint = q
                    }
                    let bounce: CGFloat = impact > 40 ? Physics.restitution : 0
                    velocity -= n * (vn * (1 + bounce))
                    let tangential = velocity - n * velocity.dot(n)
                    velocity -= tangential * min(1, Physics.friction * dt)
                }
            }
        }
        if worstImpact > Physics.crashSpeed {
            crash(at: impactPoint, cause: .impact)
        } else if worstImpact > 45 {
            events.append(.bump(worstImpact))
        }
    }

    private func checkHazards() {
        for circle in RocketShape.hull {
            let c = position + circle.offset.rotated(by: angle)
            let r = max(1, circle.radius - Physics.hazardForgiveness)

            for (k, tri) in level.spikes.enumerated() where tri.count == 3 {
                let box = spikeBoxes[k]
                if c.x + r < box.minX || c.x - r > box.maxX || c.y + r < box.minY || c.y - r > box.maxY { continue }
                if Geo.pointInTriangle(c, tri[0], tri[1], tri[2]) ||
                    Geo.distance(from: c, toSegment: tri[0], tri[1]) < r ||
                    Geo.distance(from: c, toSegment: tri[1], tri[2]) < r ||
                    Geo.distance(from: c, toSegment: tri[2], tri[0]) < r {
                    crash(at: c, cause: .hazard)
                    return
                }
            }

            for i in level.mines.indices {
                let p = minePosition(i)
                let rr = r + level.mines[i].radius
                if (c - p).lengthSquared < rr * rr {
                    crash(at: c, cause: .hazard)
                    return
                }
            }

            for i in level.spinners.indices {
                let s = level.spinners[i]
                let toHub = (c - s.center).length
                if toHub > s.length + r + 6 { continue }
                if toHub < r + 9 {
                    crash(at: c, cause: .hazard)
                    return
                }
                let base = spinnerAngle(i)
                for k in 0..<s.arms {
                    let a = base + CGFloat(k) * 2 * .pi / CGFloat(s.arms)
                    let tip = s.center + CGPoint(x: cos(a), y: sin(a)) * s.length
                    if Geo.distance(from: c, toSegment: s.center, tip) < r + 4 {
                        crash(at: c, cause: .hazard)
                        return
                    }
                }
            }

            for i in level.lasers.indices where laserState(i) == .on {
                let l = level.lasers[i]
                if Geo.distance(from: c, toSegment: l.a, l.b) < r + 1.5 {
                    crash(at: c, cause: .hazard)
                    return
                }
            }
        }
    }

    private func collectItems() {
        let r2 = Physics.pickupRadius * Physics.pickupRadius
        for (i, p) in level.stars.enumerated() where !collectedStars.contains(i) {
            if (position - p).lengthSquared < r2 {
                collectedStars.insert(i)
                events.append(.star(i))
            }
        }
        for (i, p) in level.cans.enumerated() where !collectedCans.contains(i) {
            if (position - p).lengthSquared < r2 {
                collectedCans.insert(i)
                fuel = min(level.fuel, fuel + Physics.canFuel)
                if fuelFraction >= Physics.lowFuelFraction { lowFuelWarned = false }
                events.append(.fuelCan(i))
            }
        }
        for (i, key) in level.keys.enumerated() where !collectedKeys.contains(i) {
            if (position - key.position).lengthSquared < r2 {
                collectedKeys.insert(i)
                events.append(.key(i))
                for (d, door) in level.doors.enumerated() where door.color == key.color && !openDoors.contains(d) {
                    openDoors.insert(d)
                    events.append(.doorOpened(d))
                }
            }
        }
    }

    private func updateLanding(_ dt: Double) {
        let g = level.goal
        var touching = false
        for idx in RocketShape.feet {
            let circle = RocketShape.hull[idx]
            let c = position + circle.offset.rotated(by: angle)
            let r = circle.radius
            if c.x >= g.x - g.width / 2 - r && c.x <= g.x + g.width / 2 + r &&
                c.y >= g.y - 1 && c.y - r <= g.y + 1.5 {
                touching = true
                break
            }
        }
        touchingGoal = touching
        let upright = abs(angle) < Physics.landMaxTilt
        tiltedOnGoal = touching && !upright
        let centered = abs(position.x - g.x) <= g.width / 2
        if touching && upright && centered && velocity.length < Physics.landMaxSpeed {
            landingTimer += dt
            if landingTimer >= Physics.landHoldTime {
                status = .landed
                thrusting = false
                velocity = .zero
                events.append(.landed)
            }
        } else {
            landingTimer = max(0, landingTimer - dt * 2)
        }
    }

    private func updateFuel(_ dt: Double) {
        if started && !lowFuelWarned && level.fuel > 0 && fuelFraction < Physics.lowFuelFraction {
            lowFuelWarned = true
            events.append(.lowFuel)
        }
        if fuel <= 0 && !touchingGoal && velocity.length < 6 {
            stuckTimer += dt
            if stuckTimer > 1.5 {
                status = .outOfFuel
                thrusting = false
                events.append(.outOfFuel)
            }
        } else {
            stuckTimer = 0
        }
    }

    private func crash(at point: CGPoint, cause: CrashCause) {
        guard status == .flying else { return }
        status = .crashed
        thrusting = false
        events.append(.crashed(at: point, cause: cause))
    }

    /// Test / tooling hook: teleport the rocket.
    func place(at point: CGPoint, velocity v: CGPoint = .zero, angle a: CGFloat = 0) {
        position = point
        velocity = v
        angle = a
    }
}
