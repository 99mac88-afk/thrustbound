import SpriteKit
import UIKit

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt64(s, radix: 16) ?? 0
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    func lighter(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }
}

/// Colours used by every world.
enum Palette {
    static let hazard = UIColor(hex: "#FF2E4D")
    static let hazardCore = UIColor(hex: "#FFD1D8")
    static let goal = UIColor(hex: "#44FF88")
    static let star = UIColor(hex: "#FFE14D")
    static let fuel = UIColor(hex: "#FFB020")
    static let wind = UIColor(hex: "#8FD3FF")
    static let keyColors = [UIColor(hex: "#FFC23D"), UIColor(hex: "#2EF0E0"), UIColor(hex: "#FF6AD5")]
    static let hull = UIColor(hex: "#EEF3FB")
    static let hullShade = UIColor(hex: "#9DB0C9")
    static let rocketRed = UIColor(hex: "#FF4D5E")
    static let window = UIColor(hex: "#6FD8FF")
    static let metal = UIColor(hex: "#3B4659")

    static func key(_ index: Int) -> UIColor {
        keyColors[((index % keyColors.count) + keyColors.count) % keyColors.count]
    }
}

struct Theme {
    let neon: UIColor
    let rock: UIColor
    let bgTop: UIColor
    let bgBottom: UIColor

    init(_ world: WorldInfo?) {
        neon = UIColor(hex: world?.neon ?? "#3BE3FF")
        rock = UIColor(hex: world?.rock ?? "#0E2233")
        bgTop = UIColor(hex: world?.bgTop ?? "#03070F")
        bgBottom = UIColor(hex: world?.bgBottom ?? "#0A1C30")
    }
}

/// Vector art for the rocket, in rocket space (nose up, 40pt tall, centred).
enum RocketArt {
    static var hull: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 20))
        p.addQuadCurve(to: CGPoint(x: 8, y: 4), control: CGPoint(x: 8, y: 14))
        p.addLine(to: CGPoint(x: 8, y: -12))
        p.addLine(to: CGPoint(x: -8, y: -12))
        p.addLine(to: CGPoint(x: -8, y: 4))
        p.addQuadCurve(to: CGPoint(x: 0, y: 20), control: CGPoint(x: -8, y: 14))
        p.closeSubpath()
        return p
    }

    static var nose: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 20))
        p.addQuadCurve(to: CGPoint(x: 6.6, y: 10), control: CGPoint(x: 6.2, y: 16))
        p.addLine(to: CGPoint(x: -6.6, y: 10))
        p.addQuadCurve(to: CGPoint(x: 0, y: 20), control: CGPoint(x: -6.2, y: 16))
        p.closeSubpath()
        return p
    }

    static var fins: CGPath {
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: -8, y: -1), CGPoint(x: -13, y: -12), CGPoint(x: -13, y: -20),
                             CGPoint(x: -10, y: -20), CGPoint(x: -8, y: -13)])
        p.closeSubpath()
        p.addLines(between: [CGPoint(x: 8, y: -1), CGPoint(x: 13, y: -12), CGPoint(x: 13, y: -20),
                             CGPoint(x: 10, y: -20), CGPoint(x: 8, y: -13)])
        p.closeSubpath()
        return p
    }

    static var stripe: CGPath {
        CGPath(rect: CGRect(x: -8, y: -9, width: 16, height: 3), transform: nil)
    }

    static var nozzle: CGPath {
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: -5, y: -12), CGPoint(x: 5, y: -12),
                             CGPoint(x: 6.5, y: -16), CGPoint(x: -6.5, y: -16)])
        p.closeSubpath()
        return p
    }

    static var window: CGPath {
        CGPath(ellipseIn: CGRect(x: -3.6, y: -0.6, width: 7.2, height: 7.2), transform: nil)
    }

    static func flame(length: CGFloat, width: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -width / 2, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: -length), control: CGPoint(x: -width / 2, y: -length * 0.55))
        p.addQuadCurve(to: CGPoint(x: width / 2, y: 0), control: CGPoint(x: width / 2, y: -length * 0.55))
        p.closeSubpath()
        return p
    }
}

@MainActor
enum Textures {
    static let softDot: SKTexture = {
        let size = CGSize(width: 32, height: 32)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: 16, y: 16)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: 16, options: [])
            }
        }
        return SKTexture(image: image)
    }()

    static let hardDot: SKTexture = {
        let size = CGSize(width: 8, height: 8)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }()

    static let streak: SKTexture = {
        let size = CGSize(width: 4, height: 28)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 2, y: 0), end: CGPoint(x: 2, y: 28), options: [])
            }
        }
        return SKTexture(image: image)
    }()

    static func verticalGradient(size: CGSize, top: UIColor, bottom: UIColor) -> SKTexture {
        let s = CGSize(width: max(2, size.width), height: max(2, size.height))
        let image = UIGraphicsImageRenderer(size: s).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            }
        }
        return SKTexture(image: image)
    }

    /// A beam that fades out upwards (bright at the bottom of the texture).
    static let beam: SKTexture = {
        let size = CGSize(width: 8, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
            }
        }
        return SKTexture(image: image)
    }()
}

@MainActor
enum Shapes {
    static func starPath(outer: CGFloat, inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? outer : inner
            let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    static func keyPath() -> CGPath {
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: -11, y: -5, width: 10, height: 10))
        p.addRect(CGRect(x: -2, y: -1.5, width: 13, height: 3))
        p.addRect(CGRect(x: 6, y: -6, width: 2.5, height: 5))
        p.addRect(CGRect(x: 9.5, y: -5, width: 2.5, height: 4))
        return p
    }

    static func minePath(radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let spikes = 8
        for i in 0..<(spikes * 2) {
            let a = CGFloat(i) * .pi / CGFloat(spikes)
            let rr = i % 2 == 0 ? r * 1.32 : r * 0.88
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    static func shape(_ path: CGPath, fill: UIColor?, stroke: UIColor?, lineWidth: CGFloat = 1) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill ?? .clear
        node.strokeColor = stroke ?? .clear
        node.lineWidth = stroke == nil ? 0 : lineWidth
        node.lineJoin = .round
        node.lineCap = .round
        node.isAntialiased = true
        return node
    }

    static func glow(color: UIColor, radius: CGFloat, alpha: CGFloat = 0.5) -> SKSpriteNode {
        let s = SKSpriteNode(texture: Textures.softDot)
        s.size = CGSize(width: radius * 2, height: radius * 2)
        s.color = color
        s.colorBlendFactor = 1
        s.alpha = alpha
        s.blendMode = .add
        return s
    }
}

@MainActor
enum Effects {
    static func exhaust() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.softDot
        e.particleBirthRate = 0
        e.particleLifetime = 0.42
        e.particleLifetimeRange = 0.15
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.35
        e.particleSpeed = 170
        e.particleSpeedRange = 50
        e.particleScale = 0.32
        e.particleScaleRange = 0.08
        e.particleScaleSpeed = 1.1
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -2.0
        e.particleBlendMode = .add
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor(hex: "#FFF6C2"), UIColor(hex: "#FFB13B"), UIColor(hex: "#FF4A2A"), UIColor(hex: "#5A3A55")],
            times: [0, 0.15, 0.45, 1])
        return e
    }

    static func explosion(color: UIColor) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.softDot
        e.numParticlesToEmit = 160
        e.particleBirthRate = 4000
        e.particleLifetime = 0.9
        e.particleLifetimeRange = 0.5
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = 190
        e.particleSpeedRange = 160
        e.particleScale = 0.5
        e.particleScaleRange = 0.3
        e.particleScaleSpeed = -0.4
        e.particleAlphaSpeed = -1.0
        e.particleBlendMode = .add
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.white, UIColor(hex: "#FFD25A"), color, UIColor(hex: "#3A2030")],
            times: [0, 0.1, 0.4, 1])
        e.yAcceleration = -120
        return e
    }

    static func sparkle(color: UIColor, count: Int = 24, speed: CGFloat = 120) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.softDot
        e.numParticlesToEmit = count
        e.particleBirthRate = 2000
        e.particleLifetime = 0.6
        e.particleLifetimeRange = 0.3
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.5
        e.particleScale = 0.28
        e.particleScaleRange = 0.1
        e.particleScaleSpeed = -0.35
        e.particleAlphaSpeed = -1.4
        e.particleBlendMode = .add
        e.particleColor = color
        e.particleColorBlendFactor = 1
        return e
    }

    static func confetti() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.hardDot
        e.numParticlesToEmit = 90
        e.particleBirthRate = 600
        e.particleLifetime = 1.6
        e.particleLifetimeRange = 0.6
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = 1.1
        e.particleSpeed = 260
        e.particleSpeedRange = 120
        e.yAcceleration = -320
        e.particleScale = 0.6
        e.particleScaleRange = 0.3
        e.particleAlphaSpeed = -0.5
        e.particleRotationRange = .pi
        e.particleRotationSpeed = 4
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [Palette.goal, Palette.star, Palette.window, Palette.rocketRed, Palette.goal],
            times: [0, 0.25, 0.5, 0.75, 1])
        return e
    }

    static func wind(rect: CGRect, force: CGPoint) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.streak
        let strength = max(1, force.length)
        let angle = atan2(force.y, force.x)
        let along = abs(cos(angle)) * rect.width + abs(sin(angle)) * rect.height
        e.particleBirthRate = max(6, rect.width * rect.height / 2600)
        e.particleSpeed = strength * 0.9
        e.particleSpeedRange = strength * 0.25
        e.particleLifetime = max(0.6, along / (strength * 0.9))
        e.particleLifetimeRange = e.particleLifetime * 0.3
        e.emissionAngle = angle
        e.emissionAngleRange = 0
        e.particlePositionRange = CGVector(dx: rect.width, dy: rect.height)
        e.particleRotation = angle - .pi / 2
        e.particleAlpha = 0
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.0, 0.45, 0.45, 0.0], times: [0, 0.2, 0.8, 1])
        e.particleScale = 0.9
        e.particleScaleRange = 0.4
        e.particleColor = Palette.wind
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.position = CGPoint(x: rect.midX, y: rect.midY)
        return e
    }
}
