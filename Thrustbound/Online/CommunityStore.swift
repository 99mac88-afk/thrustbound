import Foundation

/// A published level as listed in the community browser.
struct CommunityLevel: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    var views: Int
    var likes: Int
    let createdAt: Date?
    let authorID: String
    let author: String
}

enum CommunityTab: String, CaseIterable, Identifiable {
    case newest
    case top
    case viewed
    case mine

    var id: String { rawValue }

    var order: String {
        switch self {
        case .newest, .mine: return "created_at.desc"
        case .top: return "likes.desc,created_at.desc"
        case .viewed: return "views.desc,created_at.desc"
        }
    }
}

/// Browsing, playing, liking, publishing and deleting community levels.
@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var lists: [CommunityTab: [CommunityLevel]] = [:]
    @Published private(set) var loading: Set<CommunityTab> = []
    @Published private(set) var exhausted: Set<CommunityTab> = []
    @Published private(set) var errors: [CommunityTab: OnlineError] = [:]
    @Published private(set) var liked: Set<String> = []
    /// Levels whose like is being sent right now.
    @Published private(set) var liking: Set<String> = []

    let account: AccountStore
    static let pageSize = 30
    private var countedViews: Set<String> = []
    private var listedFor: [CommunityTab: String] = [:]
    private var generation: [CommunityTab: Int] = [:]

    private static let columns = "select=id,title,views,likes,created_at,author_id,author:profiles!levels_author_id_fkey(username)"

    init(account: AccountStore) {
        self.account = account
    }

    func levels(_ tab: CommunityTab) -> [CommunityLevel] { lists[tab] ?? [] }

    func find(_ id: String) -> CommunityLevel? {
        for list in lists.values {
            if let l = list.first(where: { $0.id == id }) { return l }
        }
        return nil
    }

    private func update(_ id: String, _ change: (inout CommunityLevel) -> Void) {
        for (tab, list) in lists {
            guard let i = list.firstIndex(where: { $0.id == id }) else { continue }
            var copy = list
            change(&copy[i])
            lists[tab] = copy
        }
    }

    /// Who the list was loaded for, so switching accounts reloads "Mine".
    private var viewerKey: String { (account.config?.url ?? "") + "|" + (account.userID ?? "") }

    func loadIfNeeded(_ tab: CommunityTab) async {
        if lists[tab] == nil || listedFor[tab] != viewerKey {
            await reload(tab)
        }
    }

    func reload(_ tab: CommunityTab) async {
        await load(tab, offset: 0)
    }

    func loadMore(_ tab: CommunityTab) async {
        guard !exhausted.contains(tab), !loading.contains(tab) else { return }
        await load(tab, offset: levels(tab).count)
    }

    private func load(_ tab: CommunityTab, offset: Int) async {
        guard let client = account.client else {
            errors[tab] = .notConfigured
            return
        }
        // A newer load of the same tab wins; older replies are dropped.
        let ticket = (generation[tab] ?? 0) + 1
        generation[tab] = ticket
        loading.insert(tab)
        defer { if generation[tab] == ticket { loading.remove(tab) } }
        let viewer = viewerKey
        var query = "levels?\(CommunityStore.columns)&order=\(tab.order)&limit=\(CommunityStore.pageSize)&offset=\(offset)"
        do {
            let data: Data
            if tab == .mine {
                guard let me = account.userID else { throw OnlineError.signInRequired }
                query += "&author_id=eq.\(me)"
                data = try await account.authorized { c, token in try await c.get(query, token: token) }
            } else if account.isSignedIn {
                data = try await account.authorized { c, token in try await c.get(query, token: token) }
            } else {
                data = try await client.get(query, token: nil)
            }
            let page = try CommunityStore.decodeList(data)
            guard viewer == viewerKey, generation[tab] == ticket else { return }
            var list = offset == 0 ? [] : levels(tab)
            let known = Set(list.map(\.id))
            list.append(contentsOf: page.filter { !known.contains($0.id) })
            lists[tab] = list
            listedFor[tab] = viewer
            errors[tab] = nil
            if page.count < CommunityStore.pageSize { exhausted.insert(tab) } else { exhausted.remove(tab) }
            await refreshLikes(page.map(\.id))
        } catch let e as OnlineError {
            if generation[tab] == ticket { errors[tab] = e }
        } catch {
            if generation[tab] == ticket { errors[tab] = .server(code: nil, message: "Unexpected reply") }
        }
    }

    private func refreshLikes(_ ids: [String]) async {
        guard account.isSignedIn, !ids.isEmpty else { return }
        let filter = ids.joined(separator: ",")
        guard let data = try? await account.authorized({ c, token in
            try await c.get("level_likes?select=level_id&level_id=in.(\(filter))", token: token)
        }) else { return }
        struct Row: Decodable { let level_id: String }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        let mine = Set(rows.map(\.level_id))
        for id in ids {
            if mine.contains(id) { liked.insert(id) } else { liked.remove(id) }
        }
    }

    /// Forget lists and likes (after signing in or out, or changing server).
    func reset() {
        lists = [:]
        exhausted = []
        errors = [:]
        liked = []
        listedFor = [:]
    }

    // MARK: - Playing

    /// Downloads a level and checks it can be played.
    func download(_ level: CommunityLevel) async throws -> EditorLevel {
        guard let client = account.client else { throw OnlineError.notConfigured }
        let data = try await client.get("levels?id=eq.\(level.id)&select=data", token: nil)
        struct Row: Decodable { let data: EditorLevel }
        guard let row = try? JSONDecoder().decode([Row].self, from: data).first else {
            throw OnlineError.badLevel
        }
        guard LevelCompiler.problems(row.data).isEmpty else { throw OnlineError.badLevel }
        return row.data
    }

    /// Counts a view the first time a level is played after the app starts.
    func registerView(_ id: String) {
        guard !countedViews.contains(id), let client = account.client else { return }
        countedViews.insert(id)
        Task {
            guard let data = try? await client.rpc("register_view", ["p_level": id], token: nil),
                  let views = try? JSONDecoder().decode(Int.self, from: data) else { return }
            update(id) { $0.views = views }
        }
    }

    // MARK: - Likes

    func toggleLike(_ id: String) async throws {
        guard !liking.contains(id) else { return }
        liking.insert(id)
        defer { liking.remove(id) }
        let data = try await account.authorized { c, token in
            try await c.rpc("toggle_like", ["p_level": id], token: token)
        }
        struct Reply: Decodable {
            let liked: Bool
            let likes: Int
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        if reply.liked { liked.insert(id) } else { liked.remove(id) }
        update(id) { $0.likes = reply.likes }
    }

    // MARK: - Publishing and deleting

    func canDelete(_ level: CommunityLevel) -> Bool {
        account.isAdmin || (account.userID != nil && level.authorID == account.userID)
    }

    func delete(_ level: CommunityLevel) async throws {
        let data = try await account.authorized { c, token in
            try await c.delete("levels", filter: "id=eq.\(level.id)", token: token)
        }
        // Row level security returns nothing (instead of an error) when we may not delete it.
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        guard !rows.isEmpty else { throw OnlineError.notAllowed }
        for (tab, list) in lists {
            lists[tab] = list.filter { $0.id != level.id }
        }
    }

    /// Uploads a level and returns its id on the server.
    func publish(_ level: EditorLevel) async throws -> String {
        struct NewLevel: Encodable {
            let title: String
            let data: EditorLevel
        }
        let body = try JSONEncoder().encode(NewLevel(title: level.name, data: level.publishable))
        let data = try await account.authorized { c, token in
            try await c.insert("levels", body: body, token: token)
        }
        let rows = try CommunityStore.decodeList(data)
        guard let row = rows.first else { throw OnlineError.server(code: nil, message: "Unexpected reply") }
        for tab in [CommunityTab.newest, .mine] where lists[tab] != nil {
            lists[tab] = [row] + levels(tab).filter { $0.id != row.id }
        }
        return row.id
    }

    // MARK: - Decoding

    nonisolated static func decodeList(_ data: Data) throws -> [CommunityLevel] {
        struct Author: Decodable { let username: String }
        struct Row: Decodable {
            let id: String
            let title: String
            let views: Int?
            let likes: Int?
            let created_at: String?
            let author_id: String
            let author: Author?
        }
        return try JSONDecoder().decode([Row].self, from: data).map {
            CommunityLevel(id: $0.id, title: $0.title, views: $0.views ?? 0, likes: $0.likes ?? 0,
                           createdAt: $0.created_at.flatMap(parseDate), authorID: $0.author_id,
                           author: $0.author?.username ?? "?")
        }
    }

    /// Postgres timestamps look like 2026-10-07T13:40:05.480163+00:00.
    nonisolated static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: text) { return d }
        // Drop the fraction of a second, which older iOS versions refuse when it has 6 digits.
        guard let dot = text.firstIndex(of: ".") else { return nil }
        var end = text.index(after: dot)
        while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
        return plain.date(from: String(text[..<dot]) + String(text[end...]))
    }
}
