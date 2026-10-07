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

        let renderer = LevelRenderer(root: worldNode, theme: theme, strings: strings)
        renderer.build(level)
        mineNodes = renderer.mineNodes
        spinnerNodes = renderer.spinnerNodes
        laserNodes = renderer.laserNodes
        starNodes = renderer.starNodes
        canNodes = renderer.canNodes
        keyNodes = renderer.keyNodes
        doorNodes = renderer.doorNodes

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
