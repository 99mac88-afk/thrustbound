import Combine
import Foundation

/// Saves the player's progress to their account so it follows them to every device:
/// stars and best times in the campaign, and which community levels they finished.
/// The best result always wins, so a sync is simply "send everything, keep the best of both".
@MainActor
final class ProgressSync: ObservableObject {
    enum State: Equatable {
        case idle
        case syncing
        case synced
        /// The server doesn't have sync_progress yet (its schema.sql is older).
        case unavailable
        /// Offline or another temporary problem; the next sync tries again.
        case failed
    }

    struct Reply: Equatable {
        var campaign: [Int: LevelRecord]
        var community: [String: Double]
        /// How often the account's campaign was reset (nil from servers that don't say).
        var resets: Int?
        /// The campaign was reset on another device since this one last synced: take the account's as it is.
        var replaced = false
    }

    /// Community levels finished on this device or account: level id → best time.
    @Published private(set) var clears: [String: Double] = [:]
    @Published private(set) var state: State = .idle

    /// The campaign records to send, and where the account's go (set by AppModel; true = replace instead of merge).
    var localCampaign: @MainActor () -> [Int: LevelRecord] = { [:] }
    var applyCampaign: @MainActor ([Int: LevelRecord], Bool) -> Void = { _, _ in }

    private let account: AccountStore
    private let defaults = UserDefaults.standard
    private var clearsServer = ""
    private var running = false
    private var again = false
    private var lastAttempt: Date?
    /// Bumped by Reset progress so replies to older requests don't bring the campaign back.
    private var resetGeneration = 0
    /// The account whose campaign still has to be cleared on the server.
    private var pendingResetUser: String?
    /// A server found without sync_progress (checked again after the app restarts).
    private var unavailableServer: String?
    /// The account's reset count this device last saw, per "server|user".
    private var resetsSeen: [String: Int] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    private static let clearsKey = "progress.communityClears.v1"
    private static let resetKey = "progress.pendingReset.v1"
    private static let resetsSeenKey = "progress.resetsSeen.v1"
    /// Screens sync when they open, but not more often than this.
    nonisolated static let staleAfter: TimeInterval = 60

    init(account: AccountStore) {
        self.account = account
        if let saved = defaults.dictionary(forKey: ProgressSync.clearsKey),
           let server = saved["server"] as? String, let list = saved["clears"] as? [String: Double] {
            clearsServer = server
            clears = list
        }
        pendingResetUser = defaults.string(forKey: ProgressSync.resetKey)
        resetsSeen = defaults.dictionary(forKey: ProgressSync.resetsSeenKey) as? [String: Int] ?? [:]
    }

    /// Starts following sign-ins (call once AppModel has set the closures).
    func start() {
        serverMayHaveChanged()
        account.$config
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                // @Published sends before the value changes, so look on the next turn.
                Task { @MainActor in self.serverMayHaveChanged() }
            }
            .store(in: &subscriptions)
        account.$session
            .map { $0?.userID }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] user in
                guard let self = self, user != nil else { return }
                Task { @MainActor in self.sync() }
            }
            .store(in: &subscriptions)
        sync()
    }

    // MARK: - Community levels

    func clearTime(_ levelID: String) -> Double? {
        clears[levelID.lowercased()]
    }

    /// Remembers a finished community level and saves it to the account.
    func recordClear(_ levelID: String, time: Double) -> RecordUpdate {
        serverMayHaveChanged()
        let id = levelID.lowercased()
        let old = clears[id]
        let faster = old.map { time < $0 } ?? true
        if faster {
            clears[id] = time
            saveClears()
        }
        sync()
        return RecordUpdate(newBestStars: false, newBestTime: old != nil && faster,
                            previousBestTime: old, firstClear: old == nil)
    }

    // MARK: - Syncing

    /// Sends this device's progress and takes the account's (does nothing when signed out).
    func sync() {
        guard account.isSignedIn else { return }
        if running {
            again = true
            return
        }
        running = true
        Task { await run() }
    }

    /// Syncs unless that happened in the last minute (screens call this when they open).
    func syncIfStale(now: Date = Date()) {
        if let last = lastAttempt, now.timeIntervalSince(last) < ProgressSync.staleAfter { return }
        sync()
    }

    /// Settings → Reset progress: also clears the campaign saved to the account.
    func resetCampaign() {
        resetGeneration += 1
        guard let user = account.userID else { return }
        pendingResetUser = user
        defaults.set(user, forKey: ProgressSync.resetKey)
        sync()
    }

    private func run() async {
        defer {
            running = false
            if again {
                again = false
                sync()
            }
        }
        guard let user = account.userID, let client = account.client else { return }
        let server = client.baseString
        guard unavailableServer != server else { return }
        serverMayHaveChanged()
        lastAttempt = Date()
        let generation = resetGeneration
        let reset = pendingResetUser == user
        let seenKey = server + "|" + user
        let seen: Any = resetsSeen[seenKey].map { $0 as Any } ?? NSNull()
        var campaign: [String: Any] = [:]
        for (id, r) in localCampaign() {
            campaign[String(id)] = ["stars": r.stars, "bestTime": r.bestTime]
        }
        let community = clears
        state = .syncing
        do {
            let data = try await account.authorized { c, token in
                try await c.rpc("sync_progress",
                                ["p_campaign": campaign, "p_community": community, "p_reset_campaign": reset,
                                 "p_seen_resets": seen],
                                token: token)
            }
            // Signed out or switched accounts meanwhile: this reply belongs to someone else.
            guard account.userID == user, account.client?.baseString == server else {
                state = .idle
                return
            }
            let reply = try ProgressSync.decode(data)
            if generation == resetGeneration {
                if reset {
                    pendingResetUser = nil
                    defaults.removeObject(forKey: ProgressSync.resetKey)
                }
                applyCampaign(reply.campaign, reply.replaced)
                if let resets = reply.resets {
                    resetsSeen[seenKey] = resets
                    defaults.set(resetsSeen, forKey: ProgressSync.resetsSeenKey)
                }
            }
            let merged = ProgressSync.mergeClears(clears, reply.community)
            if merged != clears {
                clears = merged
                saveClears()
            }
            state = .synced
        } catch OnlineError.server(let code, _) where code == "PGRST202" {
            unavailableServer = server
            state = .unavailable
        } catch {
            state = .failed
        }
    }

    /// Community level ids belong to one server, so a different server starts with none.
    private func serverMayHaveChanged() {
        let server = account.client?.baseString ?? ""
        guard server != clearsServer else { return }
        clearsServer = server
        clears = [:]
        saveClears()
    }

    private func saveClears() {
        defaults.set(["server": clearsServer, "clears": clears] as [String: Any], forKey: ProgressSync.clearsKey)
    }

    // MARK: - Merging (pure)

    /// The better of both for every level: the most stars and the fastest time.
    nonisolated static func merge(_ a: [Int: LevelRecord], _ b: [Int: LevelRecord]) -> [Int: LevelRecord] {
        var out = a
        for (id, r) in b {
            if let old = out[id] {
                out[id] = LevelRecord(stars: max(old.stars, r.stars), bestTime: min(old.bestTime, r.bestTime))
            } else {
                out[id] = r
            }
        }
        return out
    }

    nonisolated static func mergeClears(_ a: [String: Double], _ b: [String: Double]) -> [String: Double] {
        a.merging(b, uniquingKeysWith: min)
    }

    /// {"campaign": {"12": {"stars": 3, "bestTime": 14.2}}, "community": {"<uuid>": 21.5}}
    nonisolated static func decode(_ data: Data) throws -> Reply {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OnlineError.server(code: nil, message: "Unexpected reply")
        }
        var campaign: [Int: LevelRecord] = [:]
        for (key, value) in o["campaign"] as? [String: Any] ?? [:] {
            guard let id = Int(key), let r = value as? [String: Any],
                  let stars = (r["stars"] as? NSNumber)?.intValue,
                  let time = (r["bestTime"] as? NSNumber)?.doubleValue,
                  (0...3).contains(stars), time > 0, time.isFinite else { continue }
            campaign[id] = LevelRecord(stars: stars, bestTime: time)
        }
        var community: [String: Double] = [:]
        for (key, value) in o["community"] as? [String: Any] ?? [:] {
            guard let time = (value as? NSNumber)?.doubleValue, time > 0, time.isFinite else { continue }
            community[key.lowercased()] = time
        }
        return Reply(campaign: campaign, community: community,
                     resets: (o["resets"] as? NSNumber)?.intValue, replaced: o["replaced"] as? Bool ?? false)
    }
}
