import SpriteKit
import UIKit

/// Builds the SpriteKit nodes for a level (terrain, pads, items, hazards).
/// Shared by the game scene and the level editor so both look identical.
@MainActor
final class LevelRenderer {
    let root: SKNode
    let theme: Theme
    let strings: L10n

    private(set) var mineNodes: [SKNode] = []
    private(set) var spinnerNodes: [SKNode] = []
    private(set) var laserNodes: [LaserNode] = []
    private(set) var starNodes: [SKNode] = []
    private(set) var canNodes: [SKNode] = []
    private(set) var keyNodes: [SKNode] = []
    private(set) var doorNodes: [SKNode] = []

    init(root: SKNode, theme: Theme, strings: L10n) {
        self.root = root
        self.theme = theme
        self.strings = strings
    }

    func build(_ level: LevelData) {
        buildTerrain(level.terrain)
        buildObjects(level)
    }

    /// Everything except the rock (the editor redraws rock and objects separately).
    func buildObjects(_ level: LevelData) {
        buildBackdrop(level)
        buildWinds(level)
        buildPads(level)
        buildDoors(level)
        buildItems(level)
        buildHazards(level)
    }

    private func buildBackdrop(_ level: LevelData) {
        // A soft glow behind the goal so it reads from far away.
        let beam = SKSpriteNode(texture: Textures.beam)
        beam.anchorPoint = CGPoint(x: 0.5, y: 0)
        beam.size = CGSize(width: level.goal.width * 0.9, height: 260)
        beam.position = CGPoint(x: level.goal.x, y: level.goal.y)
        beam.color = Palette.goal
        beam.colorBlendFactor = 1
        beam.alpha = 0.16
        beam.blendMode = .add
        beam.zPosition = -6
        beam.run(.repeatForever(.sequence([.fadeAlpha(to: 0.07, duration: 1.1), .fadeAlpha(to: 0.2, duration: 1.1)])))
        root.addChild(beam)
    }

    private func buildWinds(_ level: LevelData) {
        for wind in level.winds {
            let tint = Shapes.shape(CGPath(rect: wind.rect, transform: nil),
                                    fill: Palette.wind.withAlphaComponent(0.045), stroke: Palette.wind.withAlphaComponent(0.12), lineWidth: 1)
            tint.zPosition = -5
            root.addChild(tint)
            let emitter = Effects.wind(rect: wind.rect, force: wind.force)
            emitter.zPosition = -4
            root.addChild(emitter)
            emitter.advanceSimulationTime(Double(emitter.particleLifetime))
        }
    }

    func buildTerrain(_ terrain: [[[CGPoint]]]) {
        let path = CGMutablePath()
        for polygon in terrain {
            for ring in polygon where ring.count >= 3 {
                path.addLines(between: ring)
                path.closeSubpath()
            }
        }
        let fill = Shapes.shape(path, fill: theme.rock, stroke: nil)
        fill.zPosition = 0
        root.addChild(fill)
        let glow = Shapes.shape(path, fill: nil, stroke: theme.neon.withAlphaComponent(0.22), lineWidth: 9)
        glow.blendMode = .add
        glow.zPosition = 0.5
        root.addChild(glow)
        let edge = Shapes.shape(path, fill: nil, stroke: theme.neon, lineWidth: 2.2)
        edge.zPosition = 1
        root.addChild(edge)
    }

    private func buildPads(_ level: LevelData) {
        for (pad, isGoal) in [(level.start, false), (level.goal, true)] {
            let node = SKNode()
            node.position = CGPoint(x: pad.x, y: pad.y)
            node.zPosition = 2
            let rect = CGRect(x: -pad.width / 2, y: -10, width: pad.width, height: 10)
            let base = Shapes.shape(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil),
                                    fill: isGoal ? UIColor(hex: "#0E3A22") : Palette.metal,
                                    stroke: isGoal ? Palette.goal : UIColor(hex: "#8C9AB3"), lineWidth: 1.5)
            base.zPosition = 0
            node.addChild(base)
            let top = Shapes.shape(CGPath(rect: CGRect(x: -pad.width / 2 + 1, y: -3, width: pad.width - 2, height: 3), transform: nil),
                                   fill: isGoal ? Palette.goal : UIColor(hex: "#C9D3E3"), stroke: nil)
            top.zPosition = 1
            node.addChild(top)
            for side in [-1.0, 1.0] as [CGFloat] {
                let light = Shapes.shape(CGPath(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5), transform: nil),
                                         fill: isGoal ? Palette.goal : Palette.star, stroke: nil)
                light.position = CGPoint(x: side * (pad.width / 2 - 6), y: -6.5)
                light.zPosition = 2
                node.addChild(light)
                if isGoal {
                    let halo = Shapes.glow(color: Palette.goal, radius: 10, alpha: 0.8)
                    halo.position = light.position
                    halo.zPosition = 1.5
                    node.addChild(halo)
                    let blink = SKAction.sequence([.fadeAlpha(to: 0.15, duration: 0.45), .fadeAlpha(to: 0.9, duration: 0.45)])
                    halo.run(.repeatForever(blink))
                }
            }
            if isGoal {
                let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
                label.text = strings.land
                label.fontSize = 8
                label.fontColor = UIColor.white.withAlphaComponent(0.85)
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: 0, y: -6.5)
                let room = pad.width - 22
                if label.frame.width > room, label.frame.width > 0 {
                    label.setScale(room / label.frame.width)
                }
                label.zPosition = 3
                node.addChild(label)
            }
            root.addChild(node)
        }
    }

    private func buildDoors(_ level: LevelData) {
        for door in level.doors {
            let color = Palette.key(door.color)
            let node = SKNode()
            node.position = CGPoint(x: door.rect.midX, y: door.rect.midY)
            node.zPosition = 3
            let w = door.rect.width
            let h = door.rect.height
            let body = Shapes.shape(CGPath(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: nil),
                                    fill: color.withAlphaComponent(0.3), stroke: color, lineWidth: 2)
            body.zPosition = 0
            node.addChild(body)
            let stripes = CGMutablePath()
            if w >= h {
                var x = -w / 2 + 8
                while x < w / 2 - 4 {
                    stripes.move(to: CGPoint(x: x, y: -h / 2 + 3))
                    stripes.addLine(to: CGPoint(x: x + 6, y: h / 2 - 3))
                    x += 12
                }
            } else {
                var y = -h / 2 + 8
                while y < h / 2 - 4 {
                    stripes.move(to: CGPoint(x: -w / 2 + 3, y: y))
                    stripes.addLine(to: CGPoint(x: w / 2 - 3, y: y + 6))
                    y += 12
                }
            }
            let stripeNode = Shapes.shape(stripes, fill: nil, stroke: color.withAlphaComponent(0.55), lineWidth: 2)
            stripeNode.zPosition = 1
            node.addChild(stripeNode)
            let lock = SKNode()
            lock.zPosition = 2
            let shackle = CGMutablePath()
            shackle.addArc(center: CGPoint(x: 0, y: 2), radius: 4, startAngle: 0, endAngle: .pi, clockwise: false)
            let shackleNode = Shapes.shape(shackle, fill: nil, stroke: .white, lineWidth: 2)
            lock.addChild(shackleNode)
            let lockBody = Shapes.shape(CGPath(roundedRect: CGRect(x: -6, y: -6, width: 12, height: 9),
                                               cornerWidth: 2, cornerHeight: 2, transform: nil), fill: color, stroke: .white, lineWidth: 1.2)
            lock.addChild(lockBody)
            node.addChild(lock)
            root.addChild(node)
            doorNodes.append(node)
        }
    }

    private func buildItems(_ level: LevelData) {
        for p in level.stars {
            let node = SKNode()
            node.position = p
            node.zPosition = 5
            let glow = Shapes.glow(color: Palette.star, radius: 24, alpha: 0.45)
            node.addChild(glow)
            let star = Shapes.shape(Shapes.starPath(outer: 12, inner: 5.4), fill: Palette.star, stroke: UIColor.white.withAlphaComponent(0.9), lineWidth: 1.2)
            star.zPosition = 1
            star.run(.repeatForever(.sequence([.rotate(byAngle: 0.35, duration: 0.8), .rotate(byAngle: -0.35, duration: 0.8)])))
            node.addChild(star)
            node.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.9), .moveBy(x: 0, y: -4, duration: 0.9)])))
            root.addChild(node)
            starNodes.append(node)
        }
        for p in level.cans {
            let node = SKNode()
            node.position = p
            node.zPosition = 5
            let glow = Shapes.glow(color: Palette.fuel, radius: 22, alpha: 0.4)
            node.addChild(glow)
            let body = Shapes.shape(CGPath(roundedRect: CGRect(x: -8, y: -10, width: 16, height: 20), cornerWidth: 4, cornerHeight: 4, transform: nil),
                                    fill: Palette.fuel, stroke: .white, lineWidth: 1.2)
            body.zPosition = 1
            node.addChild(body)
            let cap = Shapes.shape(CGPath(rect: CGRect(x: -3, y: 10, width: 6, height: 3), transform: nil), fill: .white, stroke: nil)
            cap.zPosition = 1
            node.addChild(cap)
            let drop = CGMutablePath()
            drop.move(to: CGPoint(x: 0, y: 6))
            drop.addQuadCurve(to: CGPoint(x: 0, y: -6), control: CGPoint(x: 7, y: -4))
            drop.addQuadCurve(to: CGPoint(x: 0, y: 6), control: CGPoint(x: -7, y: -4))
            let dropNode = Shapes.shape(drop, fill: UIColor(hex: "#5A2E00"), stroke: nil)
            dropNode.zPosition = 2
            node.addChild(dropNode)
            node.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.7), .moveBy(x: 0, y: -3, duration: 0.7)])))
            root.addChild(node)
            canNodes.append(node)
        }
        for key in level.keys {
            let color = Palette.key(key.color)
            let node = SKNode()
            node.position = key.position
            node.zPosition = 5
            let glow = Shapes.glow(color: color, radius: 24, alpha: 0.5)
            node.addChild(glow)
            let shape = Shapes.shape(Shapes.keyPath(), fill: color, stroke: .white, lineWidth: 1)
            shape.zPosition = 1
            node.addChild(shape)
            shape.run(.repeatForever(.sequence([.scaleX(to: -1, duration: 0.9), .scaleX(to: 1, duration: 0.9)])))
            root.addChild(node)
            keyNodes.append(node)
        }
    }

    private func buildHazards(_ level: LevelData) {
        if !level.spikes.isEmpty {
            let path = CGMutablePath()
            for tri in level.spikes where tri.count == 3 {
                path.addLines(between: tri)
                path.closeSubpath()
            }
            let glow = Shapes.shape(path, fill: nil, stroke: Palette.hazard.withAlphaComponent(0.35), lineWidth: 5)
            glow.blendMode = .add
            glow.zPosition = 5.5
            root.addChild(glow)
            let spikes = Shapes.shape(path, fill: Palette.hazard, stroke: Palette.hazardCore, lineWidth: 1)
            spikes.zPosition = 6
            root.addChild(spikes)
        }

        for mine in level.mines {
            let node = SKNode()
            node.position = mine.path.first ?? .zero
            node.zPosition = 6
            if mine.path.count > 1 {
                let track = CGMutablePath()
                track.addLines(between: mine.path)
                if mine.loop { track.closeSubpath() }
                let trackNode = Shapes.shape(track, fill: nil, stroke: Palette.hazard.withAlphaComponent(0.16), lineWidth: 1.5)
                trackNode.zPosition = 4
                root.addChild(trackNode)
            }
            let glow = Shapes.glow(color: Palette.hazard, radius: mine.radius * 2.6, alpha: 0.45)
            node.addChild(glow)
            let body = Shapes.shape(Shapes.minePath(radius: mine.radius), fill: Palette.hazard, stroke: Palette.hazardCore, lineWidth: 1)
            body.zPosition = 1
            body.run(.repeatForever(.rotate(byAngle: .pi, duration: 2.4)))
            node.addChild(body)
            let core = Shapes.shape(CGPath(ellipseIn: CGRect(x: -mine.radius * 0.4, y: -mine.radius * 0.4,
                                                             width: mine.radius * 0.8, height: mine.radius * 0.8), transform: nil),
                                    fill: Palette.hazardCore, stroke: nil)
            core.zPosition = 2
            core.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
            node.addChild(core)
            root.addChild(node)
            mineNodes.append(node)
        }

        for spinner in level.spinners {
            let node = SKNode()
            node.position = spinner.center
            node.zPosition = 6
            let sweep = Shapes.shape(CGPath(ellipseIn: CGRect(x: -spinner.length, y: -spinner.length,
                                                              width: spinner.length * 2, height: spinner.length * 2), transform: nil),
                                     fill: Palette.hazard.withAlphaComponent(0.04), stroke: Palette.hazard.withAlphaComponent(0.14), lineWidth: 1)
            sweep.position = spinner.center
            sweep.zPosition = 4
            root.addChild(sweep)
            for k in 0..<spinner.arms {
                let arm = SKNode()
                arm.zRotation = CGFloat(k) * 2 * .pi / CGFloat(spinner.arms)
                let blade = Shapes.shape(CGPath(roundedRect: CGRect(x: 0, y: -4, width: spinner.length, height: 8),
                                                cornerWidth: 4, cornerHeight: 4, transform: nil),
                                         fill: Palette.hazard, stroke: Palette.hazardCore, lineWidth: 1)
                blade.zPosition = 0
                arm.addChild(blade)
                let glowLine = CGMutablePath()
                glowLine.move(to: CGPoint(x: 4, y: 0))
                glowLine.addLine(to: CGPoint(x: spinner.length - 4, y: 0))
                let glow = Shapes.shape(glowLine, fill: nil, stroke: Palette.hazard.withAlphaComponent(0.4), lineWidth: 12)
                glow.blendMode = .add
                glow.zPosition = -0.5
                arm.addChild(glow)
                arm.zPosition = 1
                node.addChild(arm)
            }
            let hub = Shapes.shape(CGPath(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20), transform: nil),
                                   fill: Palette.metal, stroke: Palette.hazard, lineWidth: 2.5)
            hub.zPosition = 2
            node.addChild(hub)
            root.addChild(node)
            spinnerNodes.append(node)
        }

        for laser in level.lasers {
            let node = LaserNode(a: laser.a, b: laser.b)
            node.zPosition = 6
            root.addChild(node)
            laserNodes.append(node)
        }
    }

}
