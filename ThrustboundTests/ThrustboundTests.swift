import CoreGraphics
import XCTest
@testable import Thrustbound

final class ThrustboundTests: XCTestCase {
    private static let library = LevelLibrary.load(bundle: Bundle(for: GameWorld.self))

    private var levels: [LevelData] { Self.library.levels }

    private func level(named name: String) throws -> LevelData {
        try XCTUnwrap(levels.first { $0.name == name }, "missing level \(name)")
    }

    private func run(_ world: GameWorld, seconds: Double, input: ControlInput = ControlInput(),
                     until stop: ((GameWorld) -> Bool)? = nil) {
        var t = 0.0
        while t < seconds {
            world.step(Physics.step, input: input)
            t += Physics.step
            if let stop = stop, stop(world) { return }
        }
    }

    // MARK: - Data

    func testAllLevelsLoad() {
        XCTAssertEqual(levels.count, 40)
        XCTAssertEqual(Self.library.worlds.count, 4)
        XCTAssertEqual(Set(levels.map { $0.id }).count, levels.count, "level ids must be unique")
        for level in levels {
            XCTAssertEqual(level.stars.count, 3, level.name)
            XCTAssertFalse(level.terrain.isEmpty, level.name)
            XCTAssertGreaterThan(level.fuel, 0, level.name)
            XCTAssertGreaterThan(level.par, 0, level.name)
            XCTAssertGreaterThanOrEqual(level.width, 420, level.name)
            XCTAssertTrue((0..<4).contains(level.world), level.name)
            for door in level.doors {
                XCTAssertTrue(level.keys.contains { $0.color == door.color }, "\(level.name): door without key")
            }
        }
    }

    func testEachWorldHasTenLevels() {
        for world in 0..<4 {
            XCTAssertEqual(levels.filter { $0.world == world }.count, 10)
        }
    }

    // MARK: - Spawning

    func testRocketRestsSafelyOnEveryLaunchPad() {
        for level in levels {
            let world = GameWorld(level: level)
            run(world, seconds: 6)
            XCTAssertEqual(world.status, .flying, "\(level.name): rocket did not survive sitting on the pad")
            XCTAssertEqual(world.position.y, level.start.y + RocketShape.spawnHeight, accuracy: 1.5, level.name)
            XCTAssertEqual(world.position.x, level.start.x, accuracy: 1.5, level.name)
            XCTAssertEqual(world.fuel, level.fuel, accuracy: 0.0001, "\(level.name): fuel used without input")
            XCTAssertFalse(world.started, level.name)
        }
    }

    // MARK: - Flight

    func testThrustLiftsOffAndBurnsFuel() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        run(world, seconds: 0.8, input: ControlInput(thrust: true, targetAngle: nil))
        XCTAssertGreaterThan(world.position.y, level.start.y + 60)
        XCTAssertLessThan(world.fuel, level.fuel - 0.7)
        XCTAssertTrue(world.started)
    }

    func testSteeringPointsTheNose() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: 200, y: 500))
        run(world, seconds: 0.4, input: ControlInput(thrust: false, targetAngle: -.pi / 2))
        XCTAssertEqual(world.angle, -.pi / 2, accuracy: 0.01)
    }

    func testHardImpactCrashes() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: 100, y: 600))
        run(world, seconds: 6) { $0.status != .flying }
        XCTAssertEqual(world.status, .crashed)
    }

    func testGentleTouchdownOnGoalWins() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: level.goal.x, y: level.goal.y + RocketShape.spawnHeight + 8))
        run(world, seconds: 3) { $0.status != .flying }
        XCTAssertEqual(world.status, .landed)
    }

    func testTiltedTouchdownDoesNotWin() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: level.goal.x, y: level.goal.y + RocketShape.spawnHeight + 4), angle: 0.6)
        run(world, seconds: 2)
        XCTAssertEqual(world.status, .flying)
        XCTAssertTrue(world.tiltedOnGoal)
        // Straightening up on the pad completes the landing.
        run(world, seconds: 2, input: ControlInput(thrust: false, targetAngle: 0)) { $0.status != .flying }
        XCTAssertEqual(world.status, .landed)
    }

    func testFastTouchdownOnGoalCrashes() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: level.goal.x, y: level.goal.y + 60), velocity: CGPoint(x: 0, y: -300))
        run(world, seconds: 2) { $0.status != .flying }
        XCTAssertEqual(world.status, .crashed)
    }

    // MARK: - Items and hazards

    func testStarPickup() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.place(at: level.stars[0])
        run(world, seconds: Physics.step)
        XCTAssertTrue(world.collectedStars.contains(0))
        let events = world.drainEvents()
        XCTAssertTrue(events.contains { if case .star(0) = $0 { return true } else { return false } })
    }

    func testFuelCanRefillsUpToTankSize() throws {
        let level = try level(named: "Fuel Stop")
        let world = GameWorld(level: level)
        world.fuel = 1
        world.place(at: level.cans[0])
        run(world, seconds: Physics.step)
        XCTAssertEqual(world.fuel, min(level.fuel, 1 + Physics.canFuel), accuracy: 0.01)
    }

    func testMineDestroysRocket() throws {
        let level = try level(named: "Mine Field")
        let world = GameWorld(level: level)
        world.place(at: level.mines[0].path[0])
        run(world, seconds: Physics.step)
        XCTAssertEqual(world.status, .crashed)
    }

    func testSpikesDestroyRocket() throws {
        let level = try level(named: "Sharp Edges")
        let world = GameWorld(level: level)
        let tri = level.spikes[3]
        world.place(at: CGPoint(x: tri[2].x, y: tri[2].y + 10))
        run(world, seconds: 0.5) { $0.status != .flying }
        XCTAssertEqual(world.status, .crashed)
    }

    func testKeyOpensMatchingDoor() throws {
        let level = try level(named: "Locked Out")
        let world = GameWorld(level: level)
        XCTAssertTrue(world.openDoors.isEmpty)
        world.place(at: level.keys[0].position)
        run(world, seconds: Physics.step)
        XCTAssertEqual(world.openDoors, Set(level.doors.indices))
        XCTAssertEqual(world.heldKeyColors, [level.keys[0].color])
    }

    func testClosedDoorIsSolid() throws {
        let level = try level(named: "Locked Out")
        let world = GameWorld(level: level)
        let door = level.doors[0].rect
        // Rest on top of the closed door: the rocket must not fall through.
        world.place(at: CGPoint(x: door.midX, y: door.maxY + RocketShape.spawnHeight + 2))
        run(world, seconds: 1.5)
        XCTAssertEqual(world.status, .flying)
        XCTAssertGreaterThan(world.position.y, door.maxY + 10)
    }

    func testLaserCycles() throws {
        let level = try level(named: "Laser Gate")
        let world = GameWorld(level: level)
        run(world, seconds: 0.2)
        XCTAssertEqual(world.laserState(0), .on)
        run(world, seconds: 1.6)
        XCTAssertEqual(world.laserState(0), .off)
        run(world, seconds: 0.9)
        XCTAssertEqual(world.laserState(0), .warning)
    }

    func testOutOfFuelIsDetected() throws {
        let level = try level(named: "First Flight")
        let world = GameWorld(level: level)
        world.fuel = 0
        run(world, seconds: 3) { $0.status != .flying }
        XCTAssertEqual(world.status, .outOfFuel)
    }

    func testResetRestoresStart() throws {
        let level = try level(named: "Locked Out")
        let world = GameWorld(level: level)
        world.place(at: level.keys[0].position)
        run(world, seconds: 0.5)
        world.reset()
        XCTAssertEqual(world.status, .flying)
        XCTAssertTrue(world.openDoors.isEmpty)
        XCTAssertTrue(world.collectedKeys.isEmpty)
        XCTAssertEqual(world.fuel, level.fuel)
        XCTAssertEqual(world.position, CGPoint(x: level.start.x, y: level.start.y + RocketShape.spawnHeight))
    }

    // MARK: - Localization

    func testSystemLanguageDetection() {
        XCTAssertEqual(Lang.detect(from: ["ru-RU", "en-US"]), .ru)
        XCTAssertEqual(Lang.detect(from: ["ru"]), .ru)
        XCTAssertEqual(Lang.detect(from: ["en-GB", "ru-RU"]), .en)
        XCTAssertEqual(Lang.detect(from: ["de-DE"]), .en)
        XCTAssertEqual(Lang.detect(from: []), .en)
        XCTAssertEqual(Lang.resolve(.system, preferred: ["ru-KZ"]), .ru)
        XCTAssertEqual(Lang.resolve(.english, preferred: ["ru-RU"]), .en)
        XCTAssertEqual(Lang.resolve(.russian, preferred: ["en-US"]), .ru)
    }

    func testEveryLevelAndWorldHasRussianText() {
        let ru = L10n(.ru)
        let en = L10n(.en)
        for level in levels {
            XCTAssertFalse((level.nameRu ?? "").isEmpty, "\(level.name): missing Russian name")
            XCTAssertFalse((level.hintRu ?? "").isEmpty, "\(level.name): missing Russian hint")
            XCTAssertEqual(ru.name(level), level.nameRu)
            XCTAssertEqual(en.name(level), level.name)
            XCTAssertEqual(ru.hint(level), level.hintRu)
        }
        for (i, world) in Self.library.worlds.enumerated() {
            XCTAssertFalse((world.nameRu ?? "").isEmpty)
            XCTAssertFalse((world.subtitleRu ?? "").isEmpty)
            XCTAssertNotEqual(ru.worldName(world, index: i), en.worldName(world, index: i))
        }
    }

    func testTranslationsCoverTheSameContent() {
        let ru = L10n(.ru)
        let en = L10n(.en)
        XCTAssertEqual(ru.tips.count, en.tips.count)
        XCTAssertEqual(ru.tips.map { $0.icon }, en.tips.map { $0.icon })
        XCTAssertEqual(ru.crashTips.count, en.crashTips.count)
        XCTAssertEqual(ru.fuelTips.count, en.fuelTips.count)
        XCTAssertEqual(en.gas, "GAS")
        XCTAssertEqual(ru.gas, "ГАЗ")
        XCTAssertEqual(ru.time(12.34), "12,3 с")
        XCTAssertEqual(en.time(12.34), "12.3s")
    }

    func testRussianPlurals() {
        XCTAssertEqual(L10n(.ru).levelCount(1), "1 уровень")
        XCTAssertEqual(L10n(.ru).levelCount(3), "3 уровня")
        XCTAssertEqual(L10n(.ru).levelCount(11), "11 уровней")
        XCTAssertEqual(L10n(.ru).levelCount(22), "22 уровня")
        XCTAssertEqual(L10n(.ru).levelCount(40), "40 уровней")
        XCTAssertEqual(L10n(.en).levelCount(40), "40 levels")
    }

    func testLaunchOptionsParsing() {
        let o = LaunchOptions.parse(["app", "-screenshot", "game:12:demo"])
        XCTAssertEqual(o.screen, "game")
        XCTAssertEqual(o.level, 12)
        XCTAssertTrue(o.demo)
        XCTAssertNil(LaunchOptions.parse(["app"]).screen)
        let ru = LaunchOptions.parse(["app", "-lang", "ru", "-screenshot", "levels"])
        XCTAssertEqual(ru.lang, .ru)
        XCTAssertEqual(ru.screen, "levels")
        XCTAssertNil(LaunchOptions.parse(["app", "-lang", "xx"]).lang)
    }
}
