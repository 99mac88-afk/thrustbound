import CoreGraphics
import XCTest
@testable import Thrustbound

/// Level maker: grid model, compiler, editor tools and the community data formats.
final class MakerTests: XCTestCase {
    private func run(_ world: GameWorld, seconds: Double, input: ControlInput = ControlInput()) {
        var t = 0.0
        while t < seconds {
            world.step(Physics.step, input: input)
            t += Physics.step
        }
    }

    /// A box with a floor, a start pad on the left and a goal on the right.
    private func basicLevel(cols: Int = EditorLevel.narrowCols, rows: Int = 20) -> EditorLevel {
        var l = EditorLevel(name: "Test", cols: cols, rows: rows)
        l.start = GridCell(c: 1, r: 1)
        l.goal = GridCell(c: cols - 3, r: 1)
        return l
    }

    private func signedArea(_ ring: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in ring.indices {
            let p = ring[i]
            let q = ring[(i + 1) % ring.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    // MARK: - Grid model

    func testNewLevelHasAFloor() {
        let l = EditorLevel(name: "x")
        XCTAssertEqual(l.cols, 14)
        XCTAssertEqual(l.rows, 40)
        for c in 0..<l.cols { XCTAssertTrue(l.isRock(c, 0)) }
        XCTAssertFalse(l.isRock(3, 1))
        XCTAssertTrue(l.isRock(-1, 5), "outside the grid counts as rock")
        XCTAssertTrue(l.isRock(3, l.rows))
    }

    func testPadNeedsRockBelowAndRoomAbove() {
        var l = basicLevel()
        XCTAssertTrue(l.padFits(at: GridCell(c: 4, r: 1)))
        XCTAssertFalse(l.padFits(at: GridCell(c: 4, r: 2)), "no rock under it")
        XCTAssertFalse(l.padFits(at: GridCell(c: 13, r: 1)), "sticks out of the grid")
        l.setRock(5, 2, true)
        XCTAssertFalse(l.padFits(at: GridCell(c: 4, r: 1)), "rock in the landing space")
        XCTAssertFalse(l.padFits(at: GridCell(c: 4, r: 0)), "pads can't sit in the bottom row")
    }

    func testProblems() {
        var l = EditorLevel(name: "x")
        XCTAssertEqual(LevelCompiler.problems(l), [.noStart, .noGoal])
        l.start = GridCell(c: 1, r: 1)
        l.goal = GridCell(c: 2, r: 1)
        XCTAssertEqual(LevelCompiler.problems(l), [.padsOverlap])
        l.goal = GridCell(c: 8, r: 5)
        XCTAssertEqual(LevelCompiler.problems(l), [.goalBlocked])
        l.goal = GridCell(c: 8, r: 1)
        XCTAssertTrue(LevelCompiler.problems(l).isEmpty)
        l.setRock(1, 0, false)
        XCTAssertEqual(LevelCompiler.problems(l), [.startBlocked])
    }

    func testResizeKeepsWhatFits() {
        var l = basicLevel(cols: 28, rows: 40)
        l.setRock(20, 30, true)
        l.items = [EditorItem(kind: .star, c: 5, r: 5), EditorItem(kind: .star, c: 20, r: 35),
                   EditorItem(kind: .movingMine, c: 3, r: 3, c2: 22, r2: 3)]
        l.resize(cols: 14, rows: 20)
        XCTAssertEqual(l.cols, 14)
        XCTAssertEqual(l.rows, 20)
        XCTAssertEqual(l.rock.count, 14 * 20)
        XCTAssertTrue(l.isRock(3, 0), "floor kept")
        XCTAssertEqual(l.items.count, 1, "items outside the new size are dropped")
        XCTAssertNotNil(l.start)
        XCTAssertNil(l.goal, "goal was at column 25")
        l.resize(cols: 99, rows: 500)
        XCTAssertEqual(l.cols, 14, "only the two supported widths")
        XCTAssertEqual(l.rows, EditorLevel.maxRows)
    }

    func testCodecRoundTripAndTolerance() throws {
        var l = basicLevel()
        l.items = [EditorItem(kind: .wind, c: 4, r: 4, dir: 1), EditorItem(kind: .key, c: 5, r: 6, color: 2)]
        l.clearTime = 12.5
        l.setRock(6, 9, true)
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(EditorLevel.self, from: data)
        XCTAssertEqual(back, l)

        let messy = """
        {"cols": 14, "rows": 9999, "rock": "10", "fuel": 1000, "theme": 3,
         "items": [{"kind": "star", "c": 1, "r": 2}, {"kind": "mine", "c": 3, "r": 4, "dir": 9}]}
        """
        let m = try JSONDecoder().decode(EditorLevel.self, from: Data(messy.utf8))
        XCTAssertEqual(m.rows, EditorLevel.maxRows)
        XCTAssertEqual(m.rock.count, m.cols * m.rows)
        XCTAssertFalse(m.rock.contains(1), "a rock string of the wrong length is ignored")
        XCTAssertEqual(m.fuel, EditorLevel.fuelRange.upperBound)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.name, "Untitled")

        let many = (0..<500).map { "{\"kind\":\"star\",\"c\":1,\"r\":\($0)}" }.joined(separator: ",")
        let big = try JSONDecoder().decode(EditorLevel.self, from: Data("{\"cols\":28,\"rows\":20,\"items\":[\(many)]}".utf8))
        XCTAssertEqual(big.items.count, EditorLevel.maxItems)
        XCTAssertEqual(big.cols, 28)

        XCTAssertThrowsError(try JSONDecoder().decode(EditorLevel.self, from: Data("{\"cols\":\"x\"}".utf8)))
    }

    func testPublishableDropsLocalBookkeeping() throws {
        var l = basicLevel()
        l.updatedAt = Date()
        l.clearedHash = "abc"
        l.publishedID = "id"
        l.publishedHash = "def"
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(l.publishable), encoding: .utf8))
        for key in ["updatedAt", "clearedHash", "publishedID", "publishedHash"] {
            XCTAssertFalse(json.contains(key), key)
        }
    }

    func testContentHashTracksPlayableChanges() {
        var l = basicLevel()
        let h = l.contentHash
        l.name = "Renamed"
        l.theme = 5
        XCTAssertEqual(l.contentHash, h, "name and look don't change how it plays")
        l.fuel += 1
        XCTAssertNotEqual(l.contentHash, h)
        var m = basicLevel()
        m.setRock(7, 7, true)
        XCTAssertNotEqual(m.contentHash, basicLevel().contentHash)
        var n = basicLevel()
        n.items.append(EditorItem(kind: .star, c: 5, r: 5))
        XCTAssertNotEqual(n.contentHash, basicLevel().contentHash)
    }

    func testClearingOnlyCountsForTheExactLayout() {
        var l = basicLevel()
        let hash = l.contentHash
        l.markCleared(hash: hash, time: 20)
        XCTAssertTrue(l.isCleared)
        XCTAssertEqual(l.clearTime, 20)
        l.markCleared(hash: hash, time: 25)
        XCTAssertEqual(l.clearTime, 20, "keeps the best time")
        l.markCleared(hash: hash, time: 15)
        XCTAssertEqual(l.clearTime, 15)
        l.setRock(6, 6, true)
        XCTAssertFalse(l.isCleared, "editing makes it untested again")
        l.markCleared(hash: hash, time: 5)
        XCTAssertFalse(l.isCleared, "a clear of an older layout doesn't count")
    }

    // MARK: - Compiler

    func testOutlinesCoverExactlyTheOpenCells() {
        var rng = SeededRandom(seed: 42)
        for trial in 0..<25 {
            var l = EditorLevel(name: "r", cols: trial % 2 == 0 ? 14 : 28, rows: 20)
            for r in 0..<l.rows {
                for c in 0..<l.cols where rng.next(in: 0...1) < 0.45 {
                    l.setRock(c, r, true)
                }
            }
            let rings = LevelCompiler.rockOutlines(l)
            let open = l.rock.filter { $0 == 0 }.count
            let area = -rings.reduce(0) { $0 + signedArea($1) }
            XCTAssertEqual(area, CGFloat(open) * 900, accuracy: 0.5, "trial \(trial)")
            for ring in rings {
                XCTAssertGreaterThanOrEqual(ring.count, 4)
                for i in ring.indices {
                    let a = ring[i]
                    let b = ring[(i + 1) % ring.count]
                    XCTAssertTrue(a.x == b.x || a.y == b.y, "edges are horizontal or vertical")
                    XCTAssertNotEqual(a, b)
                }
            }
        }
    }

    func testCompiledLevelGeometry() {
        var l = basicLevel()
        l.fuel = 33
        l.clearTime = 20
        let level = LevelCompiler.compile(l, worldCount: 8)
        XCTAssertEqual(level.width, 14 * 30)
        XCTAssertEqual(level.height, 20 * 30)
        XCTAssertEqual(level.fuel, 33)
        XCTAssertEqual(level.par, 24)
        XCTAssertEqual(level.start.x, 60)
        XCTAssertEqual(level.start.y, 30)
        XCTAssertEqual(level.goal.x, 360)
        XCTAssertEqual(level.terrain.count, 1)
        XCTAssertEqual(level.terrain[0].count, 2, "outer rock and the one open room")
        XCTAssertEqual(LevelCompiler.compile(basicLevel()).par, 60, "untested levels get a default par")
    }

    func testRocketRestsOnCompiledPadAndCanLand() {
        let level = LevelCompiler.compile(basicLevel())
        let world = GameWorld(level: level)
        run(world, seconds: 5)
        XCTAssertEqual(world.status, .flying)
        XCTAssertEqual(world.position.y, level.start.y + RocketShape.spawnHeight, accuracy: 1.5)

        let landing = GameWorld(level: level)
        landing.place(at: CGPoint(x: level.goal.x, y: level.goal.y + RocketShape.spawnHeight + 4))
        run(landing, seconds: 3)
        XCTAssertEqual(landing.status, .landed)
    }

    func testPaintedRockIsSolid() {
        var l = basicLevel()
        for c in 4...9 { l.setRock(c, 8, true) }
        let level = LevelCompiler.compile(l)
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: 6.5 * 30, y: 9 * 30 + 40))
        run(world, seconds: 3)
        XCTAssertEqual(world.status, .flying)
        XCTAssertGreaterThan(world.position.y, 9 * 30, "rested on the painted shelf instead of falling through")
    }

    func testItemsCompile() {
        var l = basicLevel()
        l.setRock(2, 10, true)
        l.setRock(11, 10, true)
        l.items = [
            EditorItem(kind: .star, c: 3, r: 3),
            EditorItem(kind: .star, c: 4, r: 3),
            EditorItem(kind: .star, c: 5, r: 3),
            EditorItem(kind: .star, c: 6, r: 3),
            EditorItem(kind: .fuel, c: 4, r: 5),
            EditorItem(kind: .spikes, c: 6, r: 1),
            EditorItem(kind: .mine, c: 7, r: 6),
            EditorItem(kind: .movingMine, c: 3, r: 7, c2: 9, r2: 7),
            EditorItem(kind: .spinner, c: 6, r: 14, dir: 1, size: 2),
            EditorItem(kind: .laser, c: 5, r: 10),
            EditorItem(kind: .laser, c: 8, r: 12, dir: 1),
            EditorItem(kind: .wind, c: 8, r: 3, dir: 1),
            EditorItem(kind: .key, c: 9, r: 9, color: 1),
            EditorItem(kind: .door, c: 9, r: 15, color: 1),
            EditorItem(kind: .star, c: 0, r: 0)
        ]
        let level = LevelCompiler.compile(l)
        XCTAssertEqual(level.stars.count, 3, "at most three stars, and none inside rock")
        XCTAssertEqual(level.cans, [CGPoint(x: 135, y: 165)])
        XCTAssertEqual(level.spikes.count, 2)
        XCTAssertTrue(level.spikes.allSatisfy { $0.count == 3 })
        XCTAssertEqual(level.spikes[0][0].y, 30, "floor spikes sit on the floor")
        XCTAssertEqual(level.mines.count, 2)
        XCTAssertEqual(level.mines[1].path, [CGPoint(x: 105, y: 225), CGPoint(x: 285, y: 225)])
        XCTAssertGreaterThan(level.mines[1].speed, 0)
        XCTAssertLessThan(level.spinners[0].speed, 0, "clockwise")
        XCTAssertEqual(level.spinners[0].length, 52)
        // The across laser stops at the rock on columns 2 and 11.
        XCTAssertEqual(level.lasers[0].a.x, 3 * 30 - 4)
        XCTAssertEqual(level.lasers[0].b.x, 11 * 30 + 4)
        // The up-down laser runs from the floor to the ceiling.
        XCTAssertEqual(level.lasers[1].a.y, 30 - 4)
        XCTAssertEqual(level.lasers[1].b.y, 20 * 30 + 4)
        XCTAssertEqual(level.winds[0].force, CGPoint(x: 220, y: 0))
        XCTAssertEqual(level.keys.first?.color, 1)
        XCTAssertEqual(level.doors.first?.rect, CGRect(x: 270, y: 450, width: 30, height: 30))

        // The rocket sits safely on its pad with all of that around it.
        let world = GameWorld(level: level)
        run(world, seconds: 2)
        XCTAssertEqual(world.status, .flying)
    }

    func testSpikesDestroyTheRocket() {
        var l = basicLevel()
        l.items = [EditorItem(kind: .spikes, c: 6, r: 1)]
        let level = LevelCompiler.compile(l)
        let world = GameWorld(level: level)
        world.place(at: CGPoint(x: 6.5 * 30, y: 30 + 40))
        run(world, seconds: 2)
        XCTAssertEqual(world.status, .crashed)
    }

    func testSampleLevelIsPlayable() {
        let sample = LevelStore.sample(theme: 2)
        XCTAssertTrue(LevelCompiler.problems(sample).isEmpty)
        let level = LevelCompiler.compile(sample, worldCount: 8)
        XCTAssertEqual(level.stars.count, 3)
        XCTAssertEqual(level.world, 2)
        let world = GameWorld(level: level)
        run(world, seconds: 3)
        XCTAssertEqual(world.status, .flying)
    }

    func testThemeIsClampedToKnownWorlds() {
        var l = basicLevel()
        l.theme = 42
        XCTAssertEqual(LevelCompiler.compile(l, worldCount: 8).world, 7)
        l.theme = -3
        XCTAssertEqual(LevelCompiler.compile(l, worldCount: 8).world, 0)
    }

    // MARK: - Editor tools

    @MainActor
    private func makeSession() -> (LevelStore, EditorSession) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LevelStore(worlds: [], folder: folder)
        let level = store.create(name: "Tools", theme: 0)
        let session = try! XCTUnwrap(store.openSession(level.id))
        return (store, session)
    }

    @MainActor
    func testPaintEraseUndoRedo() {
        let (store, session) = makeSession()
        session.tool = .rock
        session.beginStroke()
        session.paint(GridCell(c: 5, r: 5))
        session.paint(GridCell(c: 6, r: 5))
        session.endStroke()
        XCTAssertTrue(session.level.isRock(5, 5))
        XCTAssertTrue(session.level.isRock(6, 5))
        XCTAssertTrue(session.canUndo)

        session.tool = .erase
        session.beginStroke()
        session.paint(GridCell(c: 5, r: 5))
        session.endStroke()
        XCTAssertFalse(session.level.isRock(5, 5))

        session.undo()
        XCTAssertTrue(session.level.isRock(5, 5))
        session.undo()
        XCTAssertFalse(session.level.isRock(6, 5))
        XCTAssertFalse(session.canUndo)
        session.redo()
        XCTAssertTrue(session.level.isRock(6, 5))
        XCTAssertEqual(store.level(session.level.id)?.rock, session.level.rock, "changes are saved")
    }

    @MainActor
    func testCancelledStrokeLeavesNoTrace() {
        let (_, session) = makeSession()
        let before = session.level
        session.tool = .rock
        session.beginStroke()
        session.paint(GridCell(c: 4, r: 4))
        session.cancelStroke()
        XCTAssertEqual(session.level, before)
        XCTAssertFalse(session.canUndo)
    }

    @MainActor
    func testRockNeverCoversPads() {
        let (_, session) = makeSession()
        let start = try! XCTUnwrap(session.level.start)
        session.tool = .rock
        session.beginStroke()
        session.paint(start)
        session.endStroke()
        XCTAssertFalse(session.level.isRock(start.c, start.r))
    }

    @MainActor
    func testPadSnapsOntoTheFloor() {
        let (_, session) = makeSession()
        session.tool = .goal
        // Tapping the floor itself puts the pad on top of it.
        session.place(GridCell(c: 6, r: 0))
        XCTAssertEqual(session.level.goal, GridCell(c: 6, r: 1))
        // Floating in the air: nothing to stand on, so it stays where it was.
        session.place(GridCell(c: 6, r: 10))
        XCTAssertEqual(session.level.goal, GridCell(c: 6, r: 1))
        XCTAssertEqual(session.notice, .padNeedsFloor)
    }

    @MainActor
    func testStarLimitAndTurningItems() {
        let (_, session) = makeSession()
        session.tool = .star
        for c in 3...6 { session.place(GridCell(c: c, r: 6)) }
        XCTAssertEqual(session.level.items.filter { $0.kind == .star }.count, 3)
        XCTAssertEqual(session.notice, .starLimit)

        session.tool = .spikes
        session.place(GridCell(c: 8, r: 1))
        XCTAssertEqual(session.level.items.last?.dir, 0, "spikes on the floor point up")
        session.place(GridCell(c: 8, r: 1))
        XCTAssertEqual(session.level.items.last?.dir, 1, "tapping again turns them")

        session.tool = .rock
        session.beginStroke()
        session.paint(GridCell(c: 8, r: 1))
        session.endStroke()
        XCTAssertFalse(session.level.items.contains { $0.c == 8 && $0.r == 1 }, "rock replaces what was there")
    }

    @MainActor
    func testMovingMineTakesTwoTaps() {
        let (_, session) = makeSession()
        session.tool = .movingMine
        session.place(GridCell(c: 3, r: 8))
        XCTAssertNotNil(session.pendingMine)
        session.place(GridCell(c: 9, r: 8))
        XCTAssertNil(session.pendingMine)
        let mine = try! XCTUnwrap(session.level.items.last)
        XCTAssertEqual(mine.kind, .movingMine)
        XCTAssertEqual(mine.c2, 9)
        XCTAssertEqual(mine.r2, 8)
    }

    @MainActor
    func testStoreSavesAndReloads() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LevelStore(worlds: [], folder: folder)
        var level = store.create(name: "Keep me", theme: 3)
        level.setRock(4, 4, true)
        store.save(level)
        let copy = store.duplicate(level.id, suffix: " copy")
        XCTAssertEqual(copy?.name, "Keep me copy")
        let reloaded = LevelStore(worlds: [], folder: folder)
        XCTAssertEqual(reloaded.levels.count, 2)
        XCTAssertEqual(reloaded.level(level.id)?.rock, level.rock)
        reloaded.delete(level.id)
        XCTAssertEqual(LevelStore(worlds: [], folder: folder).levels.count, 1)
    }

    @MainActor
    func testRecordClearMarksTheOpenLevel() {
        let (store, session) = makeSession()
        let hash = session.level.contentHash
        store.recordClear(id: session.level.id, hash: hash, time: 14)
        XCTAssertTrue(session.level.isCleared)
        XCTAssertEqual(store.level(session.level.id)?.clearTime, 14)
    }

    // MARK: - Community formats (captured from a real Supabase server)

    func testDecodeCommunityList() throws {
        let json = """
        [{"id":"e3a998ef-68d6-488f-aebb-68729fa06e0f","title":"Alice Peak","views":3,"likes":1,
          "created_at":"2026-10-07T13:40:05.480163+00:00","author_id":"a07aa859-22c5-4a4a-ac35-437e80183536",
          "author":{"username":"alice"}}]
        """
        let list = try CommunityStore.decodeList(Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].title, "Alice Peak")
        XCTAssertEqual(list[0].author, "alice")
        XCTAssertEqual(list[0].views, 3)
        XCTAssertEqual(list[0].likes, 1)
        let date = try XCTUnwrap(list[0].createdAt)
        XCTAssertEqual(date.timeIntervalSince1970, 1791380405, accuracy: 1)
        XCTAssertNotNil(CommunityStore.parseDate("2026-10-07T13:40:05+00:00"))
        XCTAssertNil(CommunityStore.parseDate("yesterday"))
    }

    func testServerErrorsMapToFriendlyCases() {
        func map(_ json: String, _ status: Int) -> OnlineError {
            SupabaseClient.error(from: Data(json.utf8), status: status)
        }
        XCTAssertEqual(map(#"{"code":"P0001","message":"That username is already taken"}"#, 500), .usernameTaken)
        XCTAssertEqual(map(#"{"code":"P0001","message":"Username must be 3-20 letters, numbers or underscores"}"#, 500), .badUsername)
        XCTAssertEqual(map(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#, 400),
                       .server(code: "invalid_credentials", message: "Invalid login credentials"))
        XCTAssertEqual(map(#"{"code":"42501","message":"permission denied for table levels"}"#, 401), .signInRequired)
        XCTAssertEqual(map(#"{"code":"42501","message":"permission denied for table levels"}"#, 403), .notAllowed)
        XCTAssertEqual(map(#"{"code":"PGRST301","message":"JWT expired"}"#, 401), .signInRequired)
        let limit = map(#"{"code":"P0001","message":"Daily publish limit reached (20 levels)"}"#, 400)
        XCTAssertTrue(L10n(.en).onlineError(limit).contains("20"))
        XCTAssertEqual(L10n(.en).onlineError(map(#"{"error_code":"user_already_exists","msg":"User already registered"}"#, 422)),
                       "An account with this email already exists.")
    }

    func testBackendConfig() {
        XCTAssertTrue(BackendConfig(url: "https://abc.supabase.co/", anonKey: "k").isUsable)
        XCTAssertEqual(BackendConfig(url: "https://abc.supabase.co//", anonKey: "k").baseURL?.absoluteString, "https://abc.supabase.co")
        XCTAssertFalse(BackendConfig(url: "abc.supabase.co", anonKey: "k").isUsable)
        XCTAssertFalse(BackendConfig(url: "https://abc.supabase.co", anonKey: " ").isUsable)
        XCTAssertTrue(AccountStore.isValidUsername("Pilot_7"))
        XCTAssertFalse(AccountStore.isValidUsername("ab"))
        XCTAssertFalse(AccountStore.isValidUsername("space man"))
        XCTAssertFalse(AccountStore.isValidUsername("пилот"))
    }

    func testMakerTextExistsInBothLanguages() {
        let en = L10n(.en)
        let ru = L10n(.ru)
        for tool in EditorTool.allCases {
            XCTAssertFalse(ru.toolName(tool).isEmpty)
            XCTAssertNotEqual(ru.toolHint(tool), en.toolHint(tool))
        }
        for tab in CommunityTab.allCases {
            XCTAssertNotEqual(ru.tabName(tab), en.tabName(tab))
        }
        XCTAssertEqual(ru.viewsCount(21), "21 просмотр")
        XCTAssertEqual(ru.likesCount(3), "3 лайка")
        XCTAssertEqual(en.likesCount(1), "1 like")
    }
}
