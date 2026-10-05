import SpriteKit
import UIKit

// MARK: - Rocket

final class RocketNode: SKNode {
    let exhaust: SKEmitterNode
    private let flameOuter: SKShapeNode
    private let flameInner: SKShapeNode
    private let flameGlow: SKSpriteNode
    private var flameLevel: CGFloat = 0

    override init() {
        exhaust = Effects.exhaust()
        flameOuter = Shapes.shape(RocketArt.flame(length: 24, width: 10), fill: UIColor(hex: "#FF7A2E"), stroke: nil)
        flameInner = Shapes.shape(RocketArt.flame(length: 13, width: 6), fill: UIColor(hex: "#FFF4B0"), stroke: nil)
        flameGlow = Shapes.glow(color: UIColor(hex: "#FF9A3D"), radius: 26, alpha: 0)
        super.init()
        exhaust.position = CGPoint(x: 0, y: -17)
        exhaust.zPosition = -3
        addChild(exhaust)

        flameGlow.position = CGPoint(x: 0, y: -22)
        flameGlow.zPosition = -2
        addChild(flameGlow)

        for (node, z) in [(flameOuter, CGFloat(-1.5)), (flameInner, CGFloat(-1.4))] {
            node.position = CGPoint(x: 0, y: -15)
            node.zPosition = z
            node.blendMode = .add
            node.yScale = 0.001
            node.alpha = 0
            addChild(node)
        }

        let fins = Shapes.shape(RocketArt.fins, fill: Palette.rocketRed, stroke: Palette.rocketRed.lighter(0.3), lineWidth: 1)
        fins.zPosition = 0
        addChild(fins)

        let nozzle = Shapes.shape(RocketArt.nozzle, fill: Palette.metal, stroke: UIColor(hex: "#788499"), lineWidth: 1)
        nozzle.zPosition = 0.5
        addChild(nozzle)

        let hull = Shapes.shape(RocketArt.hull, fill: Palette.hull, stroke: Palette.hullShade, lineWidth: 1.2)
        hull.zPosition = 1
        addChild(hull)

        let stripe = Shapes.shape(RocketArt.stripe, fill: Palette.rocketRed, stroke: nil)
        stripe.zPosition = 2
        addChild(stripe)

        let nose = Shapes.shape(RocketArt.nose, fill: Palette.rocketRed, stroke: nil)
        nose.zPosition = 2
        addChild(nose)

        let window = Shapes.shape(RocketArt.window, fill: Palette.window, stroke: .white, lineWidth: 1.2)
        window.zPosition = 3
        addChild(window)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setThrust(_ on: Bool, dt: CGFloat) {
        let target: CGFloat = on ? 1 : 0
        flameLevel += (target - flameLevel) * min(1, dt * 20)
        if flameLevel < 0.01 { flameLevel = target == 0 ? 0 : flameLevel }
        let flicker = CGFloat.random(in: 0.82...1.18)
        flameOuter.yScale = max(0.001, flameLevel * flicker)
        flameOuter.xScale = 0.75 + 0.25 * flameLevel
        flameOuter.alpha = flameLevel
        flameInner.yScale = max(0.001, flameLevel * CGFloat.random(in: 0.85...1.15))
        flameInner.alpha = flameLevel
        flameGlow.alpha = 0.55 * flameLevel
        exhaust.particleBirthRate = on ? 240 : 0
    }
}

// MARK: - Lasers

final class LaserNode: SKNode {
    private let glow: SKShapeNode
    private let core: SKShapeNode

    init(a: CGPoint, b: CGPoint) {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        glow = Shapes.shape(path, fill: nil, stroke: Palette.hazard.withAlphaComponent(0.45), lineWidth: 9)
        core = Shapes.shape(path, fill: nil, stroke: Palette.hazardCore, lineWidth: 2.4)
        super.init()
        let ghost = Shapes.shape(path, fill: nil, stroke: Palette.hazard.withAlphaComponent(0.2), lineWidth: 1)
        ghost.zPosition = 0
        addChild(ghost)
        glow.blendMode = .add
        glow.zPosition = 1
        addChild(glow)
        core.zPosition = 2
        addChild(core)

        let angle = atan2(b.y - a.y, b.x - a.x)
        for p in [a, b] {
            let box = Shapes.shape(CGPath(roundedRect: CGRect(x: -6, y: -6, width: 12, height: 12),
                                          cornerWidth: 2, cornerHeight: 2, transform: nil),
                                   fill: Palette.metal, stroke: UIColor(hex: "#8C9AB3"), lineWidth: 1)
            box.position = p
            box.zRotation = angle
            box.zPosition = 3
            let light = Shapes.shape(CGPath(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5), transform: nil),
                                     fill: Palette.hazard, stroke: nil)
            light.zPosition = 1
            box.addChild(light)
            addChild(box)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ state: LaserState, time: Double) {
        switch state {
        case .on:
            glow.isHidden = false
            core.isHidden = false
            core.alpha = 1
            glow.alpha = 0.75 + 0.25 * CGFloat(sin(time * 38))
        case .off:
            glow.isHidden = true
            core.isHidden = true
        case .warning:
            glow.isHidden = true
            core.isHidden = false
            core.alpha = Int(time * 14) % 2 == 0 ? 0.45 : 0.08
        }
    }
}

// MARK: - On-screen controls (lives on the camera, positions are screen points from centre)

final class ControlsNode: SKNode {
    let baseRadius: CGFloat = 62
    let knobRadius: CGFloat = 27
    let gasRadius: CGFloat = 54
    static let deadZone: CGFloat = 0.22

    private let joyBase: SKShapeNode
    private let joyKnob: SKShapeNode
    private let joyLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let gasButton: SKShapeNode
    private let gasGlow: SKSpriteNode
    private let gasLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let gasFlame: SKShapeNode

    private(set) var joyHome: CGPoint = .zero
    private(set) var joyCenter: CGPoint = .zero
    private(set) var gasCenter: CGPoint = .zero
    private(set) var reservedBottom: CGFloat = 200
    private(set) var reservedTop: CGFloat = 100
    private var hudLimitY: CGFloat = 0
    private var viewSize: CGSize = .zero
    private var insets: UIEdgeInsets = .zero
    var swapped = false
    var accent: UIColor = UIColor(hex: "#3BE3FF") { didSet { applyAccent() } }

    override init() {
        joyBase = Shapes.shape(CGPath(ellipseIn: CGRect(x: -62, y: -62, width: 124, height: 124), transform: nil),
                               fill: UIColor.white.withAlphaComponent(0.06), stroke: UIColor.white.withAlphaComponent(0.28), lineWidth: 2)
        joyKnob = Shapes.shape(CGPath(ellipseIn: CGRect(x: -27, y: -27, width: 54, height: 54), transform: nil),
                               fill: UIColor.white.withAlphaComponent(0.85), stroke: .white, lineWidth: 2)
        gasButton = Shapes.shape(CGPath(ellipseIn: CGRect(x: -54, y: -54, width: 108, height: 108), transform: nil),
                                 fill: UIColor.white.withAlphaComponent(0.1), stroke: .white, lineWidth: 2.5)
        gasGlow = Shapes.glow(color: .white, radius: 90, alpha: 0)
        gasFlame = Shapes.shape(RocketArt.flame(length: 20, width: 14), fill: .white, stroke: nil)
        super.init()

        joyBase.zPosition = 0
        addChild(joyBase)
        for i in 0..<4 {
            let tick = Shapes.shape(CGPath(rect: CGRect(x: -1.5, y: 44, width: 3, height: 10), transform: nil),
                                    fill: UIColor.white.withAlphaComponent(0.35), stroke: nil)
            tick.zRotation = CGFloat(i) * .pi / 2
            tick.zPosition = 0.5
            joyBase.addChild(tick)
        }
        joyKnob.zPosition = 2
        addChild(joyKnob)
        joyLabel.text = "STEER"
        joyLabel.fontSize = 11
        joyLabel.fontColor = UIColor.white.withAlphaComponent(0.45)
        joyLabel.verticalAlignmentMode = .center
        joyLabel.zPosition = 1
        addChild(joyLabel)

        gasGlow.zPosition = -1
        addChild(gasGlow)
        gasButton.zPosition = 0
        addChild(gasButton)
        gasFlame.position = CGPoint(x: 0, y: 22)
        gasFlame.zPosition = 1
        gasButton.addChild(gasFlame)
        gasLabel.text = "GAS"
        gasLabel.fontSize = 22
        gasLabel.fontColor = .white
        gasLabel.verticalAlignmentMode = .center
        gasLabel.position = CGPoint(x: 0, y: -10)
        gasLabel.zPosition = 1
        gasButton.addChild(gasLabel)
        applyAccent()
        setJoystickIdle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyAccent() {
        joyKnob.strokeColor = accent
        gasButton.strokeColor = accent
        gasButton.fillColor = accent.withAlphaComponent(0.16)
        gasFlame.fillColor = accent.lighter(0.4)
        gasGlow.color = accent
    }

    func layout(size: CGSize, insets: UIEdgeInsets) {
        viewSize = size
        self.insets = insets
        let bottomMargin = max(insets.bottom, 12) + 22
        let y = -size.height / 2 + bottomMargin + baseRadius
        let side: CGFloat = swapped ? 1 : -1
        joyHome = CGPoint(x: side * (size.width / 2 - 24 - baseRadius), y: y)
        gasCenter = CGPoint(x: -side * (size.width / 2 - 26 - gasRadius), y: y)
        gasButton.position = gasCenter
        gasGlow.position = gasCenter
        reservedBottom = bottomMargin + baseRadius * 2 + 16
        reservedTop = insets.top + 96
        hudLimitY = size.height / 2 - insets.top - 92
        setJoystickIdle()
    }

    func isJoystickZone(_ p: CGPoint) -> Bool {
        guard p.y < hudLimitY else { return false }
        return swapped ? p.x > 0 : p.x < 0
    }

    func isGasZone(_ p: CGPoint) -> Bool {
        guard p.y < hudLimitY else { return false }
        return swapped ? p.x <= 0 : p.x >= 0
    }

    /// Starts a joystick drag. If the finger lands away from the stick, the stick jumps under it.
    @discardableResult
    func beginJoystick(at p: CGPoint) -> CGPoint {
        if (p - joyHome).length > baseRadius * 1.1 {
            let margin = baseRadius + 8
            let halfW = viewSize.width / 2
            var c = p
            c.x = min(max(c.x, -halfW + margin), halfW - margin)
            c.y = min(max(c.y, -viewSize.height / 2 + margin), hudLimitY - margin)
            joyCenter = c
        } else {
            joyCenter = joyHome
        }
        joyBase.position = joyCenter
        joyLabel.position = CGPoint(x: joyCenter.x, y: joyCenter.y - baseRadius - 14)
        joyBase.alpha = 1
        joyKnob.alpha = 1
        return moveJoystick(to: p)
    }

    /// Returns the stick vector with length <= 1.
    func moveJoystick(to p: CGPoint) -> CGPoint {
        var v = p - joyCenter
        let len = v.length
        if len > baseRadius { v = v * (baseRadius / len) }
        joyKnob.position = joyCenter + v
        return v * (1 / baseRadius)
    }

    func endJoystick() {
        setJoystickIdle()
    }

    private func setJoystickIdle() {
        joyCenter = joyHome
        joyBase.position = joyHome
        joyKnob.position = joyHome
        joyLabel.position = CGPoint(x: joyHome.x, y: joyHome.y - baseRadius - 14)
        joyBase.alpha = 0.75
        joyKnob.alpha = 0.7
    }

    func setGas(pressed: Bool) {
        gasButton.setScale(pressed ? 0.92 : 1)
        gasButton.fillColor = accent.withAlphaComponent(pressed ? 0.5 : 0.16)
        gasGlow.alpha = pressed ? 0.35 : 0
    }
}

// MARK: - Parallax star field (lives on the camera)

final class StarfieldNode: SKNode {
    private struct Star {
        let node: SKSpriteNode
        let base: CGPoint
        let factor: CGFloat
    }

    private var stars: [Star] = []
    private var fieldSize: CGSize = .zero

    func layout(size: CGSize, tint: UIColor) {
        removeAllChildren()
        stars.removeAll()
        fieldSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        var rng = SeededRandom(seed: 7)
        let count = Int(fieldSize.width * fieldSize.height / 2600)
        let sizes: [CGFloat] = [2.2, 3.4, 5.0]
        let alphas: [Double] = [0.35, 0.55, 0.8]
        let factors: [CGFloat] = [0.04, 0.1, 0.2]
        for i in 0..<count {
            let layer = i % 3
            let node = SKSpriteNode(texture: Textures.softDot)
            let s: CGFloat = sizes[layer] * CGFloat(rng.next(in: 0.7...1.3))
            node.size = CGSize(width: s, height: s)
            node.color = rng.next(in: 0...1) < 0.25 ? tint.lighter(0.5) : .white
            node.colorBlendFactor = 1
            node.alpha = CGFloat(alphas[layer] * rng.next(in: 0.6...1.0))
            node.zPosition = CGFloat(layer)
            addChild(node)
            if rng.next(in: 0...1) < 0.2 {
                let a = node.alpha
                let dur = rng.next(in: 0.8...2.2)
                node.run(.repeatForever(.sequence([.fadeAlpha(to: a * 0.3, duration: dur), .fadeAlpha(to: a, duration: dur)])))
            }
            let base = CGPoint(x: CGFloat(rng.next(in: 0...1)) * fieldSize.width, y: CGFloat(rng.next(in: 0...1)) * fieldSize.height)
            stars.append(Star(node: node, base: base, factor: factors[layer]))
        }
    }

    func update(camera: CGPoint, scale: CGFloat) {
        guard fieldSize.width > 1 else { return }
        let w = fieldSize.width
        let h = fieldSize.height
        let inv = 1 / max(scale, 0.01)
        for s in stars {
            var x = (s.base.x - camera.x * s.factor * inv).truncatingRemainder(dividingBy: w)
            var y = (s.base.y - camera.y * s.factor * inv).truncatingRemainder(dividingBy: h)
            if x < 0 { x += w }
            if y < 0 { y += h }
            s.node.position = CGPoint(x: x - w / 2, y: y - h / 2)
        }
    }
}

/// Small deterministic RNG so layouts look the same every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15 | 1
    }

    mutating func nextUInt() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt() % 1_000_000) / 999_999.0
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
