import SpriteKit
import UIKit

struct HUDState: Equatable {
    var fuel: Double = 1
    var stars: Int = 0
    var keys: [Int] = []
    var elapsed: Double = 0
    var speedRatio: Double = 0
    var landing: Double = 0
    var tilted = false
    var started = false
}

/// Renders a level, runs the fixed-step simulation and turns touches into input.
final class GameScene: SKScene {
    weak var session: GameSession?

    private(set) var world: GameWorld?
    private var worldInfo: WorldInfo?
    private var theme = Theme(nil)

    private let worldNode = SKNode()
    private let cam = SKCameraNode()
    private let background = SKSpriteNode()
    private let starfield = StarfieldNode()
    private let controls: ControlsNode
    private let goalArrow = SKNode()
    private var rocket: RocketNode

    private var mineNodes: [SKNode] = []
    private var spinnerNodes: [SKNode] = []
    private var laserNodes: [LaserNode] = []
    private var starNodes: [SKNode] = []
    private var canNodes: [SKNode] = []
    private var keyNodes: [SKNode] = []
    private var doorNodes: [SKNode] = []

    private var joystickTouch: UITouch?
    private var gasTouches = Set<UITouch>()
    private var targetAngle: CGFloat?

    private var lastUpdate: TimeInterval = 0
    private var accumulator: Double = 0
    private var gamePaused = false
    private var finished = false
    private var cameraBase: CGPoint = .zero
    private var shake: CGFloat = 0
    private var lastInsets: UIEdgeInsets = .zero
    private var hudTimer: Double = 0
    private var wasThrusting = false
    private var demoClock: Double = 0
    private var outcomeDelay: Double = 0
    private var outcomeAction: (() -> Void)?

    /// World units visible across the screen, regardless of device width.
    let visibleWidth: CGFloat = 420

    var swapControls = false {
        didSet {
            controls.swapped = swapControls
            controls.layout(size: size, insets: lastInsets)
        }
    }
    var demoMode = false
    /// Text for labels drawn inside the scene.
    var strings = L10n(.en) {
        didSet { controls.setLabels(gas: strings.gas, steer: strings.steer) }
    }

    var canPause: Bool { !finished && world?.status == .flying }

    override init(size: CGSize) {
        controls = ControlsNode()
        rocket = RocketNode()
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        worldNode.zPosition = 0
        addChild(worldNode)
        addChild(cam)
        camera = cam
        background.zPosition = -100
        cam.addChild(background)
        starfield.zPosition = -90
        cam.addChild(starfield)
        goalArrow.zPosition = 40
        cam.addChild(goalArrow)
        controls.zPosition = 50
        cam.addChild(controls)
        buildGoalArrow()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Level setup

    func load(level: LevelData, world info: WorldInfo?) {
        outcomeAction = nil
        worldNode.removeAllChildren()
        worldNode.isPaused = false
        mineNodes.removeAll()
        spinnerNodes.removeAll()
        laserNodes.removeAll()
        starNodes.removeAll()
        canNodes.removeAll()
        keyNodes.removeAll()
        doorNodes.removeAll()

        worldInfo = info
        theme = Theme(info)
        let w = GameWorld(level: level)
        world = w

        buildBackdrop(level)
        buildWinds(level)
        buildTerrain(level)
        buildPads(level)
        buildDoors(level)
        buildItems(level)
        buildHazards(level)

        rocket = RocketNode()
        rocket.zPosition = 10
        rocket.exhaust.targetNode = worldNode
        worldNode.addChild(rocket)

        gamePaused = false
        finished = false
        accumulator = 0
        lastUpdate = 0
        hudTimer = 0
        demoClock = 0
        shake = 0
        releaseInput()
        controls.accent = theme.neon
        refreshScreenLayout()
        syncNodes(dt: 0)
        cameraBase = cameraTarget()
        cam.position = cameraBase
        starfield.update(camera: cam.position, scale: cam.xScale)
        pushHUD()
    }

    func setGamePaused(_ paused: Bool) {
        gamePaused = paused
        worldNode.isPaused = paused
        if paused { releaseInput() }
        lastUpdate = 0
    }

    private func releaseInput() {
        joystickTouch = nil
        gasTouches.removeAll()
        controls.endJoystick()
        controls.setGas(pressed: false)
        if wasThrusting {
            wasThrusting = false
            SoundManager.shared.setThrust(false)
        }
    }

    // MARK: - Layout

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshScreenLayout()
        if world != nil {
            cameraBase = cameraTarget()
            cam.position = cameraBase
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        refreshScreenLayout()
    }

    private func refreshScreenLayout() {
        guard size.width > 1, size.height > 1 else { return }
        lastInsets = view?.safeAreaInsets ?? lastInsets
        cam.setScale(visibleWidth / size.width)
        background.texture = Textures.verticalGradient(size: CGSize(width: 8, height: 256), top: theme.bgTop, bottom: theme.bgBottom)
        background.size = CGSize(width: size.width + 4, height: size.height + 4)
        starfield.layout(size: size, tint: theme.neon)
        controls.swapped = swapControls
        controls.layout(size: size, insets: lastInsets)
    }

    private func checkInsets() {
        guard let v = view else { return }
        if v.safeAreaInsets != lastInsets {
            lastInsets = v.safeAreaInsets
            controls.layout(size: size, insets: lastInsets)
        }
    }

    // MARK: - Builders

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
        worldNode.addChild(beam)
    }

    private func buildWinds(_ level: LevelData) {
        for wind in level.winds {
            let tint = Shapes.shape(CGPath(rect: wind.rect, transform: nil),
                                    fill: Palette.wind.withAlphaComponent(0.045), stroke: Palette.wind.withAlphaComponent(0.12), lineWidth: 1)
            tint.zPosition = -5
            worldNode.addChild(tint)
            let emitter = Effects.wind(rect: wind.rect, force: wind.force)
            emitter.zPosition = -4
            worldNode.addChild(emitter)
            emitter.advanceSimulationTime(Double(emitter.particleLifetime))
        }
    }

    private func buildTerrain(_ level: LevelData) {
        let path = CGMutablePath()
        for polygon in level.terrain {
            for ring in polygon where ring.count >= 3 {
                path.addLines(between: ring)
                path.closeSubpath()
            }
        }
        let fill = Shapes.shape(path, fill: theme.rock, stroke: nil)
        fill.zPosition = 0
        worldNode.addChild(fill)
        let glow = Shapes.shape(path, fill: nil, stroke: theme.neon.withAlphaComponent(0.22), lineWidth: 9)
        glow.blendMode = .add
        glow.zPosition = 0.5
        worldNode.addChild(glow)
        let edge = Shapes.shape(path, fill: nil, stroke: theme.neon, lineWidth: 2.2)
        edge.zPosition = 1
        worldNode.addChild(edge)
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
            worldNode.addChild(node)
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
            worldNode.addChild(node)
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
            worldNode.addChild(node)
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
            worldNode.addChild(node)
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
            worldNode.addChild(node)
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
            worldNode.addChild(glow)
            let spikes = Shapes.shape(path, fill: Palette.hazard, stroke: Palette.hazardCore, lineWidth: 1)
            spikes.zPosition = 6
            worldNode.addChild(spikes)
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
                worldNode.addChild(trackNode)
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
            worldNode.addChild(node)
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
            worldNode.addChild(sweep)
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
            worldNode.addChild(node)
            spinnerNodes.append(node)
        }

        for laser in level.lasers {
            let node = LaserNode(a: laser.a, b: laser.b)
            node.zPosition = 6
            worldNode.addChild(node)
            laserNodes.append(node)
        }
    }

    private func buildGoalArrow() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 14))
        path.addLine(to: CGPoint(x: 11, y: -8))
        path.addLine(to: CGPoint(x: 0, y: -3))
        path.addLine(to: CGPoint(x: -11, y: -8))
        path.closeSubpath()
        let glow = Shapes.glow(color: Palette.goal, radius: 22, alpha: 0.45)
        goalArrow.addChild(glow)
        let arrow = Shapes.shape(path, fill: Palette.goal, stroke: .white, lineWidth: 1.2)
        arrow.zPosition = 1
        goalArrow.addChild(arrow)
        goalArrow.isHidden = true
        goalArrow.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.5), .scale(to: 1.0, duration: 0.5)])))
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        lastUpdate = currentTime
        dt = min(max(dt, 0), 1.0 / 20.0)
        checkInsets()
        guard let world = world, !gamePaused else { return }

        let input = currentInput(dt: dt)
        accumulator += dt
        var steps = 0
        while accumulator >= Physics.step && steps < 60 {
            world.step(Physics.step, input: input)
            accumulator -= Physics.step
            steps += 1
        }
        handle(world.drainEvents())

        let thrusting = world.thrusting && !finished
        if thrusting != wasThrusting {
            wasThrusting = thrusting
            SoundManager.shared.setThrust(thrusting)
        }

        syncNodes(dt: CGFloat(dt))
        updateCamera(dt: CGFloat(dt))
        if let action = outcomeAction {
            outcomeDelay -= dt
            if outcomeDelay <= 0 {
                outcomeAction = nil
                action()
            }
        }
        hudTimer += dt
        if hudTimer >= 0.05 {
            hudTimer = 0
            pushHUD()
        }
    }

    private func currentInput(dt: Double) -> ControlInput {
        var input = ControlInput()
        if finished { return input }
        input.thrust = !gasTouches.isEmpty
        input.targetAngle = targetAngle
        if demoMode, let world = world {
            demoClock += dt
            if demoClock > 0.4 {
                let level = world.level
                input.targetAngle = world.position.x < level.width / 2 ? -0.22 : 0.22
                input.thrust = world.position.y < level.start.y + 150 || world.velocity.y < -15
            }
        }
        return input
    }

    private func syncNodes(dt: CGFloat) {
        guard let world = world else { return }
        rocket.position = world.position
        rocket.zRotation = world.angle
        rocket.setThrust(world.thrusting && !finished, dt: dt)
        for (i, node) in mineNodes.enumerated() {
            node.position = world.minePosition(i)
        }
        for (i, node) in spinnerNodes.enumerated() {
            node.zRotation = world.spinnerAngle(i)
        }
        for (i, node) in laserNodes.enumerated() {
            node.apply(world.laserState(i), time: world.time)
        }
    }

    private func pushHUD() {
        guard let world = world else { return }
        var s = HUDState()
        s.fuel = world.fuelFraction
        s.stars = world.collectedStars.count
        s.keys = world.heldKeyColors
        s.elapsed = world.flightTime
        s.speedRatio = Double(world.velocity.length / Physics.crashSpeed)
        s.landing = world.landingProgress
        s.tilted = world.tiltedOnGoal
        s.started = world.started
        session?.updateHUD(s)
    }

    // MARK: - Camera

    private func cameraTarget() -> CGPoint {
        guard let world = world, size.width > 1 else { return .zero }
        let scale = cam.xScale
        let viewW = size.width * scale
        let viewH = size.height * scale
        let bottomUI = controls.reservedBottom * scale
        let topUI = controls.reservedTop * scale
        let look = CGPoint(x: max(-90, min(90, world.velocity.x * 0.18)),
                           y: max(-110, min(110, world.velocity.y * 0.22)))
        var target = world.position + look
        target.y -= (bottomUI - topUI) / 2
        let level = world.level
        let minX = viewW / 2
        let maxX = level.width - viewW / 2
        target.x = minX > maxX ? level.width / 2 : min(max(target.x, minX), maxX)
        let minY = viewH / 2 - bottomUI
        let maxY = level.height - viewH / 2 + topUI
        target.y = minY > maxY ? (minY + maxY) / 2 : min(max(target.y, minY), maxY)
        return target
    }

    private func updateCamera(dt: CGFloat) {
        let target = cameraTarget()
        let k = 1 - exp(-dt * 6)
        cameraBase = cameraBase + (target - cameraBase) * k
        var offset = CGPoint.zero
        if shake > 0.1 {
            offset = CGPoint(x: CGFloat.random(in: -shake...shake), y: CGFloat.random(in: -shake...shake))
            shake *= exp(-dt * 7)
        } else {
            shake = 0
        }
        cam.position = cameraBase + offset
        starfield.update(camera: cam.position, scale: cam.xScale)
        updateGoalArrow()
    }

    private func updateGoalArrow() {
        guard let world = world, size.width > 1 else { return }
        let scale = cam.xScale
        let goal = CGPoint(x: world.level.goal.x, y: world.level.goal.y + 10)
        let rel = (goal - cam.position) * (1 / scale)
        let halfW = size.width / 2 - 34
        let yMin = -size.height / 2 + controls.reservedBottom + 10
        let yMax = size.height / 2 - controls.reservedTop - 10
        guard yMax > yMin else { goalArrow.isHidden = true; return }
        let center = CGPoint(x: 0, y: (yMin + yMax) / 2)
        let halfH = (yMax - yMin) / 2
        let dir = rel - center
        let tx = abs(dir.x) > 0.001 ? halfW / abs(dir.x) : .greatestFiniteMagnitude
        let ty = abs(dir.y) > 0.001 ? halfH / abs(dir.y) : .greatestFiniteMagnitude
        let t = min(tx, ty)
        if t >= 1 || finished {
            goalArrow.isHidden = true
            return
        }
        goalArrow.isHidden = false
        goalArrow.position = center + dir * t
        goalArrow.zRotation = atan2(dir.y, dir.x) - .pi / 2
    }

    // MARK: - Events

    private func handle(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .star(let i):
                collect(starNodes, i, color: Palette.star)
                SoundManager.shared.play(.star)
                Haptics.light()
            case .fuelCan(let i):
                collect(canNodes, i, color: Palette.fuel)
                popup(strings.plusFuel, at: canNodes.indices.contains(i) ? canNodes[i].position : rocket.position, color: Palette.fuel)
                SoundManager.shared.play(.fuel)
                Haptics.light()
            case .key(let i):
                collect(keyNodes, i, color: Palette.key(world?.level.keys[i].color ?? 0))
                SoundManager.shared.play(.key)
                Haptics.medium()
            case .doorOpened(let i):
                openDoor(i)
                SoundManager.shared.play(.door)
            case .crashed(let point, _):
                explode(at: point)
            case .landed:
                celebrate()
            case .outOfFuel:
                finished = true
                schedule(after: 0.3) { [weak self] in self?.session?.didRunOutOfFuel() }
                SoundManager.shared.play(.lowFuel)
                Haptics.failure()
            case .bump(let speed):
                let v = Float(min(1, speed / Physics.crashSpeed))
                SoundManager.shared.play(.bump, volume: 0.3 + 0.7 * v)
                Haptics.impact(CGFloat(v))
            case .lowFuel:
                SoundManager.shared.play(.lowFuel, volume: 0.7)
                popup(strings.lowFuel, at: rocket.position + CGPoint(x: 0, y: 34), color: Palette.hazard)
            }
        }
    }

    private func schedule(after delay: Double, _ action: @escaping () -> Void) {
        outcomeDelay = delay
        outcomeAction = action
    }

    private func collect(_ nodes: [SKNode], _ index: Int, color: UIColor) {
        guard nodes.indices.contains(index) else { return }
        let node = nodes[index]
        node.removeAllActions()
        node.run(.sequence([.group([.scale(to: 1.9, duration: 0.22), .fadeOut(withDuration: 0.22)]), .removeFromParent()]))
        let sparkle = Effects.sparkle(color: color)
        sparkle.position = node.position
        sparkle.zPosition = 12
        worldNode.addChild(sparkle)
        sparkle.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    private func openDoor(_ index: Int) {
        guard doorNodes.indices.contains(index) else { return }
        let node = doorNodes[index]
        node.run(.sequence([.group([.fadeOut(withDuration: 0.4), .scale(to: 0.2, duration: 0.4)]), .removeFromParent()]))
        if let door = world?.level.doors[index] {
            let sparkle = Effects.sparkle(color: Palette.key(door.color), count: 40, speed: 90)
            sparkle.position = node.position
            sparkle.zPosition = 12
            worldNode.addChild(sparkle)
            sparkle.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
        }
    }

    private func popup(_ text: String, at point: CGPoint, color: UIColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 14
        label.fontColor = color
        label.position = point + CGPoint(x: 0, y: 18)
        label.zPosition = 20
        worldNode.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 0.9), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
                             .removeFromParent()]))
    }

    private func explode(at point: CGPoint) {
        finished = true
        releaseInput()
        // Blow up between the hull centre and the contact point.
        let center = rocket.position + (point - rocket.position) * 0.4
        rocket.exhaust.particleBirthRate = 0
        rocket.run(.sequence([.group([.scale(to: 0.3, duration: 0.12), .fadeOut(withDuration: 0.12)]), .hide()]))

        let boom = Effects.explosion(color: Palette.rocketRed)
        boom.position = center
        boom.zPosition = 12
        worldNode.addChild(boom)
        boom.run(.sequence([.wait(forDuration: 2.0), .removeFromParent()]))

        let flash = Shapes.glow(color: UIColor(hex: "#FFD25A"), radius: 30, alpha: 0.9)
        flash.position = center
        flash.zPosition = 13
        worldNode.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 5, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))

        for i in 0..<9 {
            let piece = CGMutablePath()
            piece.addLines(between: [CGPoint(x: -3, y: -2), CGPoint(x: 4, y: -1), CGPoint(x: 0, y: 4)])
            piece.closeSubpath()
            let color = i % 3 == 0 ? Palette.rocketRed : Palette.hull
            let shard = Shapes.shape(piece, fill: color, stroke: nil)
            shard.position = center
            shard.zPosition = 12
            worldNode.addChild(shard)
            let a = CGFloat(i) / 9 * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let dist = CGFloat.random(in: 50...120)
            let move = SKAction.moveBy(x: cos(a) * dist, y: sin(a) * dist - 30, duration: 0.9)
            move.timingMode = .easeOut
            shard.run(.sequence([.group([move, .rotate(byAngle: CGFloat.random(in: -8...8), duration: 0.9),
                                         .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
                                 .removeFromParent()]))
        }
        shake = 12
        SoundManager.shared.play(.crash)
        Haptics.heavy()
        schedule(after: 1.1) { [weak self] in self?.session?.didCrash() }
    }

    private func celebrate() {
        guard let world = world else { return }
        finished = true
        releaseInput()
        let confetti = Effects.confetti()
        confetti.position = CGPoint(x: world.level.goal.x, y: world.level.goal.y + 6)
        confetti.zPosition = 12
        worldNode.addChild(confetti)
        confetti.run(.sequence([.wait(forDuration: 3), .removeFromParent()]))
        SoundManager.shared.play(.land)
        Haptics.success()
        let stars = world.collectedStars.count
        let time = world.flightTime
        let fuel = world.fuelFraction
        schedule(after: 1.0) { [weak self] in
            self?.session?.didWin(stars: stars, time: time, fuelLeft: fuel)
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gamePaused, !finished else { return }
        for touch in touches {
            let p = touch.location(in: cam)
            if controls.isJoystickZone(p) {
                if joystickTouch == nil {
                    joystickTouch = touch
                    applyStick(controls.beginJoystick(at: p))
                }
            } else if controls.isGasZone(p) {
                gasTouches.insert(touch)
                controls.setGas(pressed: true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gamePaused, !finished else { return }
        for touch in touches where touch == joystickTouch {
            applyStick(controls.moveJoystick(to: touch.location(in: cam)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch == joystickTouch {
                joystickTouch = nil
                controls.endJoystick()
            }
            gasTouches.remove(touch)
        }
        controls.setGas(pressed: !gasTouches.isEmpty)
    }

    private func applyStick(_ v: CGPoint) {
        if v.length >= ControlsNode.deadZone {
            targetAngle = atan2(-v.x, v.y)
        }
    }
}
