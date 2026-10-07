import SpriteKit
import UIKit

/// The level-maker canvas. One finger uses the current tool, two fingers pan and zoom.
final class EditorScene: SKScene {
    weak var session: EditorSession?

    private let cam = SKCameraNode()
    private let background = SKSpriteNode()
    private let content = SKNode()
    private let terrainLayer = SKNode()
    private let objectLayer = SKNode()
    private let overlayLayer = SKNode()
    private let gridLayer = SKNode()
    private let cursor = SKShapeNode()

    private var shownRock: [UInt8] = []
    private var shownSize = (cols: 0, rows: 0)
    private var shownObjects: ObjectSignature?
    private var shownTheme = -1
    private var shownPending: Int??
    private var theme = Theme(nil)
    private var framed = false
    private var userMovedCamera = false

    // Touch state
    private var activeTouches: [UITouch] = []
    private var strokeTouch: UITouch?
    private var strokeCancelled = false
    private var lastCell: GridCell?
    private var pinch: PinchStart?
    private var dragStart: (view: CGPoint, camera: CGPoint)?

    private struct PinchStart {
        let center: CGPoint
        let distance: CGFloat
        let camera: CGPoint
        let scale: CGFloat
    }

    /// The parts of a level that the object layer is drawn from.
    private struct ObjectSignature: Equatable {
        let items: [EditorItem]
        let start: GridCell?
        let goal: GridCell?
        let rock: [UInt8]
        let cols: Int
        let rows: Int
        let theme: Int
    }

    private let cell = LevelCompiler.cell

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        addChild(content)
        addChild(cam)
        camera = cam
        background.zPosition = -100
        cam.addChild(background)
        terrainLayer.zPosition = 0
        content.addChild(terrainLayer)
        gridLayer.zPosition = 1.6
        content.addChild(gridLayer)
        objectLayer.zPosition = 2
        content.addChild(objectLayer)
        overlayLayer.zPosition = 30
        content.addChild(overlayLayer)
        cursor.zPosition = 40
        cursor.lineWidth = 2
        cursor.isHidden = true
        content.addChild(cursor)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.isMultipleTouchEnabled = true
        layoutBackground()
        if !framed { frameLevel() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutBackground()
        if size.width > 1 && session != nil && (!framed || !userMovedCamera) { frameLevel() }
        clampCamera()
    }

    /// Forget what is on screen so the next frame draws everything again.
    func redrawAll() {
        shownTheme = -1
        shownSize = (0, 0)
        shownRock = []
        shownObjects = nil
    }

    private func layoutBackground() {
        guard size.width > 1 else { return }
        background.texture = Textures.verticalGradient(size: CGSize(width: 8, height: 256), top: theme.bgTop, bottom: theme.bgBottom)
        background.size = CGSize(width: size.width + 4, height: size.height + 4)
    }

    // MARK: - Camera

    private var levelSize: CGSize {
        guard let l = session?.level else { return CGSize(width: 420, height: 1200) }
        return CGSize(width: CGFloat(l.cols) * cell, height: CGFloat(l.rows) * cell)
    }

    private var scaleRange: ClosedRange<CGFloat> {
        guard size.width > 1, size.height > 1 else { return 0.2...10 }
        let s = levelSize
        let minScale = 150 / size.width
        let fitAll = max((s.width + 120) / size.width, (s.height + 120) / size.height)
        return minScale...max(minScale * 1.5, fitAll)
    }

    /// Fit the level's width and look at the bottom, where the start usually is.
    func frameLevel() {
        guard size.width > 1, size.height > 1 else { return }
        framed = true
        let s = levelSize
        let scale = min(max((s.width + 40) / size.width, scaleRange.lowerBound), scaleRange.upperBound)
        cam.setScale(scale)
        var focus = CGPoint(x: s.width / 2, y: size.height * scale / 2 - 30)
        if let start = session?.level.start {
            focus.y = max(focus.y, CGFloat(start.r) * cell - size.height * scale * 0.25)
        }
        cam.position = focus
        clampCamera()
    }

    private func clampCamera() {
        let s = levelSize
        let margin: CGFloat = 80
        let viewW = size.width * cam.xScale
        let viewH = size.height * cam.yScale
        var p = cam.position
        if viewW >= s.width + margin * 2 {
            p.x = s.width / 2
        } else {
            p.x = min(max(p.x, viewW / 2 - margin), s.width + margin - viewW / 2)
        }
        if viewH >= s.height + margin * 2 {
            p.y = s.height / 2
        } else {
            p.y = min(max(p.y, viewH / 2 - margin), s.height + margin - viewH / 2)
        }
        cam.position = p
    }

    // MARK: - Drawing

    override func update(_ currentTime: TimeInterval) {
        guard let session = session else { return }
        let level = session.level
        if level.theme != shownTheme {
            shownTheme = level.theme
            let app = session.worldInfo(level.theme)
            theme = Theme(app)
            layoutBackground()
            shownRock = []
            shownObjects = nil
        }
        if level.cols != shownSize.cols || level.rows != shownSize.rows {
            shownSize = (level.cols, level.rows)
            drawGrid(level)
            clampCamera()
        }
        if level.rock != shownRock {
            shownRock = level.rock
            terrainLayer.removeAllChildren()
            let s = levelSize
            let outer = [CGPoint(x: -400, y: -400), CGPoint(x: s.width + 400, y: -400),
                         CGPoint(x: s.width + 400, y: s.height + 400), CGPoint(x: -400, y: s.height + 400)]
            let renderer = LevelRenderer(root: terrainLayer, theme: theme, strings: session.strings)
            renderer.buildTerrain([[outer] + LevelCompiler.rockOutlines(level)])
        }
        let signature = ObjectSignature(items: level.items, start: level.start, goal: level.goal, rock: level.rock,
                                        cols: level.cols, rows: level.rows, theme: level.theme)
        if signature != shownObjects || shownPending != .some(session.pendingMine) {
            shownObjects = signature
            shownPending = .some(session.pendingMine)
            drawObjects(level, pending: session.pendingMine)
        }
    }

    private func drawGrid(_ level: EditorLevel) {
        gridLayer.removeAllChildren()
        let w = CGFloat(level.cols) * cell
        let h = CGFloat(level.rows) * cell
        let fine = CGMutablePath()
        let bold = CGMutablePath()
        for c in 0...level.cols {
            let x = CGFloat(c) * cell
            let path = c % 5 == 0 ? bold : fine
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: h))
        }
        for r in 0...level.rows {
            let y = CGFloat(r) * cell
            let path = r % 5 == 0 ? bold : fine
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
        }
        let fineNode = Shapes.shape(fine, fill: nil, stroke: UIColor.white.withAlphaComponent(0.07), lineWidth: 1)
        gridLayer.addChild(fineNode)
        let boldNode = Shapes.shape(bold, fill: nil, stroke: UIColor.white.withAlphaComponent(0.15), lineWidth: 1)
        gridLayer.addChild(boldNode)
        let frame = Shapes.shape(CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil),
                                 fill: nil, stroke: UIColor.white.withAlphaComponent(0.45), lineWidth: 2)
        gridLayer.addChild(frame)
    }

    private func drawObjects(_ level: EditorLevel, pending: Int?) {
        objectLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        guard let session = session else { return }
        let compiled = LevelCompiler.compile(level, worldCount: session.worldCount, withTerrain: false)
        let renderer = LevelRenderer(root: objectLayer, theme: theme, strings: session.strings)
        renderer.buildObjects(compiled)
        for node in renderer.laserNodes { node.apply(.on, time: 0) }
        for (i, node) in renderer.spinnerNodes.enumerated() where compiled.spinners.indices.contains(i) {
            let speed = compiled.spinners[i].speed
            node.run(.repeatForever(.rotate(byAngle: speed > 0 ? .pi : -.pi, duration: .pi / abs(Double(speed)))))
        }
        for (i, node) in renderer.mineNodes.enumerated() where compiled.mines.indices.contains(i) {
            let mine = compiled.mines[i]
            guard mine.path.count == 2, mine.speed > 0 else { continue }
            let d = Double((mine.path[1] - mine.path[0]).length / mine.speed)
            let there = SKAction.move(to: mine.path[1], duration: d)
            let back = SKAction.move(to: mine.path[0], duration: d)
            there.timingMode = .easeInEaseOut
            back.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([there, back])))
        }

        // The rocket waiting on the start pad.
        if let start = level.start {
            let rocket = RocketNode()
            rocket.exhaust.particleBirthRate = 0
            rocket.position = CGPoint(x: CGFloat(start.c + 1) * cell, y: CGFloat(start.r) * cell + RocketShape.spawnHeight)
            rocket.zPosition = 10
            objectLayer.addChild(rocket)
        }

        // Pads that can't be landed on, and the mine waiting for its track.
        for pad in [level.start, level.goal].compactMap({ $0 }) where !level.padFits(at: pad) {
            let rect = CGRect(x: CGFloat(pad.c) * cell, y: CGFloat(pad.r - 1) * cell, width: cell * 2, height: cell * 3)
            let warn = Shapes.shape(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil),
                                    fill: Palette.hazard.withAlphaComponent(0.18), stroke: Palette.hazard, lineWidth: 2)
            warn.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
            overlayLayer.addChild(warn)
        }
        if let index = pending, level.items.indices.contains(index) {
            let item = level.items[index]
            let rect = CGRect(x: CGFloat(item.c) * cell + 1, y: CGFloat(item.r) * cell + 1, width: cell - 2, height: cell - 2)
            let ring = Shapes.shape(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil),
                                    fill: nil, stroke: Palette.star, lineWidth: 2.5)
            ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)])))
            overlayLayer.addChild(ring)
        }
        // Small arrows on wind cells so their direction reads even when still.
        for item in level.items where item.kind == .wind && !level.isRock(item.c, item.r) {
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: 0, y: 8))
            arrow.addLine(to: CGPoint(x: 6, y: -2))
            arrow.addLine(to: CGPoint(x: 2, y: -2))
            arrow.addLine(to: CGPoint(x: 2, y: -8))
            arrow.addLine(to: CGPoint(x: -2, y: -8))
            arrow.addLine(to: CGPoint(x: -2, y: -2))
            arrow.addLine(to: CGPoint(x: -6, y: -2))
            arrow.closeSubpath()
            let node = Shapes.shape(arrow, fill: Palette.wind.withAlphaComponent(0.8), stroke: nil)
            node.position = CGPoint(x: (CGFloat(item.c) + 0.5) * cell, y: (CGFloat(item.r) + 0.5) * cell)
            node.zRotation = -CGFloat(item.dir) * .pi / 2
            overlayLayer.addChild(node)
        }
    }

    // MARK: - Touches

    private func gridCell(at p: CGPoint) -> GridCell {
        GridCell(c: Int(floor(p.x / cell)), r: Int(floor(p.y / cell)))
    }

    private func showCursor(at c: GridCell) {
        guard let session = session else { return }
        let tool = session.tool
        guard tool != .hand else { cursor.isHidden = true; return }
        var rect = CGRect(x: CGFloat(c.c) * cell, y: CGFloat(c.r) * cell, width: cell, height: cell)
        if tool == .start || tool == .goal {
            rect = CGRect(x: CGFloat(c.c) * cell, y: CGFloat(c.r) * cell, width: cell * 2, height: cell * 2)
        }
        cursor.path = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        let color: UIColor = tool == .erase ? Palette.hazard : .white
        cursor.strokeColor = color
        cursor.fillColor = color.withAlphaComponent(0.12)
        cursor.isHidden = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let session = session, let view = view else { return }
        for t in touches where !activeTouches.contains(t) { activeTouches.append(t) }

        if activeTouches.count >= 2 {
            // Two fingers: undo whatever the first finger started and switch to pan/zoom.
            if strokeTouch != nil && !strokeCancelled {
                session.cancelStroke()
                strokeCancelled = true
            }
            strokeTouch = nil
            dragStart = nil
            cursor.isHidden = true
            beginPinch(in: view)
            return
        }

        guard let touch = activeTouches.first else { return }
        if session.tool == .hand {
            dragStart = (touch.location(in: view), cam.position)
            userMovedCamera = true
            return
        }
        strokeTouch = touch
        strokeCancelled = false
        session.beginStroke()
        let c = gridCell(at: touch.location(in: content))
        lastCell = c
        showCursor(at: c)
        if session.tool.paints { session.paint(c) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let session = session, let view = view else { return }
        if activeTouches.count >= 2, let start = pinch {
            updatePinch(start, in: view)
            return
        }
        if let drag = dragStart, let touch = activeTouches.first {
            let p = touch.location(in: view)
            cam.position = CGPoint(x: drag.camera.x - (p.x - drag.view.x) * cam.xScale,
                                   y: drag.camera.y + (p.y - drag.view.y) * cam.yScale)
            clampCamera()
            return
        }
        guard let touch = strokeTouch, touches.contains(touch), !strokeCancelled else { return }
        let c = gridCell(at: touch.location(in: content))
        if session.tool.paints, let from = lastCell {
            for step in cellsBetween(from, c) { session.paint(step) }
        }
        lastCell = c
        showCursor(at: c)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let session = session else { return }
        if let touch = strokeTouch, touches.contains(touch) {
            if cancelled {
                session.cancelStroke()
            } else if !strokeCancelled {
                if !session.tool.paints, let c = lastCell { session.place(c) }
                session.endStroke()
            }
            strokeTouch = nil
            cursor.isHidden = true
        }
        activeTouches.removeAll { touches.contains($0) }
        if activeTouches.count < 2 { pinch = nil }
        if activeTouches.isEmpty {
            dragStart = nil
            strokeCancelled = false
        } else if activeTouches.count == 1, session.tool == .hand, let view = view, let t = activeTouches.first {
            dragStart = (t.location(in: view), cam.position)
        }
    }

    private func beginPinch(in view: SKView) {
        guard activeTouches.count >= 2 else { return }
        userMovedCamera = true
        let a = activeTouches[0].location(in: view)
        let b = activeTouches[1].location(in: view)
        pinch = PinchStart(center: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                           distance: max(10, (a - b).length), camera: cam.position, scale: cam.xScale)
    }

    private func updatePinch(_ start: PinchStart, in view: SKView) {
        let a = activeTouches[0].location(in: view)
        let b = activeTouches[1].location(in: view)
        let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let distance = max(10, (a - b).length)
        let range = scaleRange
        let scale = min(max(start.scale * start.distance / distance, range.lowerBound), range.upperBound)
        // Keep the world point that was under the fingers under the fingers.
        let half = CGPoint(x: size.width / 2, y: size.height / 2)
        let anchor = CGPoint(x: start.camera.x + (start.center.x - half.x) * start.scale,
                             y: start.camera.y - (start.center.y - half.y) * start.scale)
        cam.setScale(scale)
        cam.position = CGPoint(x: anchor.x - (center.x - half.x) * scale,
                               y: anchor.y + (center.y - half.y) * scale)
        clampCamera()
    }

    /// Every cell on the straight line between two cells, so fast strokes leave no gaps.
    private func cellsBetween(_ a: GridCell, _ b: GridCell) -> [GridCell] {
        var cells: [GridCell] = []
        var x = a.c
        var y = a.r
        let dx = abs(b.c - a.c)
        let dy = -abs(b.r - a.r)
        let sx = a.c < b.c ? 1 : -1
        let sy = a.r < b.r ? 1 : -1
        var err = dx + dy
        var guardCount = 0
        while guardCount < 1000 {
            guardCount += 1
            cells.append(GridCell(c: x, r: y))
            if x == b.c && y == b.r { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x += sx
            }
            if e2 <= dx {
                err += dx
                y += sy
            }
        }
        return cells
    }
}
