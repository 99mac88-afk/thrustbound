import Foundation

/// The player's community account: server settings, sign-in state and profile.
@MainActor
final class AccountStore: ObservableObject {
    struct Profile: Equatable {
        let username: String
        let isAdmin: Bool
    }

    /// A new account waiting for the code from its confirmation email.
    struct PendingSignUp: Codable, Equatable {
        let email: String
        let server: String
        var codeSentAt: Date
    }

    @Published private(set) var config: BackendConfig?
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: Profile?
    /// True when the server was typed in by the player instead of built into the app.
    @Published private(set) var usingCustomServer = false
    @Published private(set) var pending: PendingSignUp?

    private let bundledConfig: BackendConfig?
    private var refreshTask: Task<AuthSession, Error>?
    private let defaults = UserDefaults.standard
    private static let serverKey = "community.server.v1"
    private static let profileKey = "community.profile.v1"
    private static let sessionAccount = "session"
    private static let pendingKey = "community.pending.v1"

    nonisolated static let usernamePattern = "^[A-Za-z0-9_]{3,20}$"
    /// How long to wait before offering to send another code.
    nonisolated static let resendDelay: TimeInterval = 60

    init(bundled: BackendConfig? = BackendConfig.bundled()) {
        bundledConfig = bundled
        if let data = defaults.data(forKey: AccountStore.serverKey),
           let custom = try? JSONDecoder().decode(BackendConfig.self, from: data), custom.isUsable {
            config = custom
            usingCustomServer = true
        } else {
            config = bundled
        }
        if let data = SecureStore.load(account: AccountStore.sessionAccount),
           let saved = try? JSONDecoder().decode(AuthSession.self, from: data),
           saved.server == client?.baseString {
            session = saved
            if let p = defaults.dictionary(forKey: AccountStore.profileKey),
               let name = p["username"] as? String, (p["user"] as? String) == saved.userID {
                profile = Profile(username: name, isAdmin: p["admin"] as? Bool ?? false)
            }
        }
        if session != nil {
            Task { await refreshProfile() }
        } else if let data = defaults.data(forKey: AccountStore.pendingKey),
                  let saved = try? JSONDecoder().decode(PendingSignUp.self, from: data),
                  saved.server == client?.baseString, saved.codeSentAt.timeIntervalSinceNow > -2 * 86400 {
            pending = saved
        }
    }

    var client: SupabaseClient? { config.flatMap { SupabaseClient($0) } }
    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { session != nil }
    var isAdmin: Bool { profile?.isAdmin ?? false }
    var userID: String? { session?.userID }
    var hasBundledServer: Bool { bundledConfig != nil }

    nonisolated static func isValidUsername(_ name: String) -> Bool {
        name.range(of: usernamePattern, options: .regularExpression) != nil
    }

    /// Keeps only the digits of a typed or pasted code (Supabase codes have 6 to 10 digits).
    nonisolated static func cleanCode(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(10))
    }

    nonisolated static func isCompleteCode(_ code: String) -> Bool {
        code.count >= 6 && code.count <= 10 && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Server

    func setServer(url: String, key: String) -> Bool {
        let config = BackendConfig(url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                   anonKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
        guard config.isUsable else { return false }
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: AccountStore.serverKey) }
        if config != self.config { clearSession() }
        self.config = config
        usingCustomServer = true
        return true
    }

    func useBuiltInServer() {
        defaults.removeObject(forKey: AccountStore.serverKey)
        if bundledConfig != config { clearSession() }
        config = bundledConfig
        usingCustomServer = false
    }

    // MARK: - Signing in and out

    /// Returns false when the server emailed a code that has to be entered before the account works.
    @discardableResult
    func signUp(username: String, email: String, password: String) async throws -> Bool {
        guard let client = client else { throw OnlineError.notConfigured }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AccountStore.isValidUsername(name) else { throw OnlineError.badUsername }
        guard try await client.usernameAvailable(name) else { throw OnlineError.usernameTaken }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s = try await client.signUp(email: email, password: password, username: name) else {
            setPending(PendingSignUp(email: email, server: client.baseString, codeSentAt: Date()))
            return false
        }
        store(s)
        await refreshProfile()
        return true
    }

    /// Throws `confirmEmail` (after asking for a fresh code) when the account's email isn't confirmed yet.
    func signIn(email: String, password: String) async throws {
        guard let client = client else { throw OnlineError.notConfigured }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let s: AuthSession
        do {
            s = try await client.signIn(email: email, password: password)
        } catch OnlineError.server(let code, _) where code == "email_not_confirmed" {
            // The old code may have run out, so send a new one right away.
            let sent = (try? await client.resendCode(email)) != nil
            setPending(PendingSignUp(email: email, server: client.baseString, codeSentAt: sent ? Date() : .distantPast))
            throw OnlineError.confirmEmail
        }
        store(s)
        await refreshProfile()
    }

    /// Finishes a sign-up with the code from the email and signs in.
    func confirmEmail(code: String) async throws {
        guard let client = client else { throw OnlineError.notConfigured }
        guard let p = pending else { throw OnlineError.signInRequired }
        let s = try await client.verifyEmail(p.email, code: AccountStore.cleanCode(code))
        store(s)
        await refreshProfile()
    }

    func resendCode() async throws {
        guard let client = client else { throw OnlineError.notConfigured }
        guard var p = pending else { throw OnlineError.signInRequired }
        try await client.resendCode(p.email)
        p.codeSentAt = Date()
        setPending(p)
    }

    /// Seconds until another code may be requested (0 when it can be sent now).
    func resendWait(now: Date = Date()) -> Int {
        guard let p = pending else { return 0 }
        return max(0, Int((AccountStore.resendDelay - now.timeIntervalSince(p.codeSentAt)).rounded(.up)))
    }

    /// Screenshots only: shows the code step for a made-up address without contacting the server.
    func previewCodeStep(email: String) {
        pending = PendingSignUp(email: email, server: client?.baseString ?? "", codeSentAt: Date())
    }

    /// Forgets the account that was waiting for its code (to use another email or sign in instead).
    func cancelPending() {
        setPending(nil)
    }

    private func setPending(_ p: PendingSignUp?) {
        pending = p
        if let p = p, let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: AccountStore.pendingKey)
        } else {
            defaults.removeObject(forKey: AccountStore.pendingKey)
        }
    }

    func signOut() async {
        let token = session?.accessToken
        let c = client
        clearSession()
        if let token = token, let c = c { await c.signOut(token: token) }
    }

    private func store(_ s: AuthSession) {
        session = s
        if pending != nil { setPending(nil) }
        if let data = try? JSONEncoder().encode(s) { SecureStore.save(data, account: AccountStore.sessionAccount) }
    }

    private func clearSession() {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        profile = nil
        setPending(nil)
        SecureStore.delete(account: AccountStore.sessionAccount)
        defaults.removeObject(forKey: AccountStore.profileKey)
    }

    // MARK: - Tokens

    /// A fresh access token, refreshing it first when it is about to run out.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = session else { throw OnlineError.signInRequired }
        if !forceRefresh && current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        guard let client = client else { throw OnlineError.notConfigured }
        let task: Task<AuthSession, Error>
        if let running = refreshTask {
            task = running
        } else {
            let refreshToken = current.refreshToken
            task = Task { try await client.refresh(refreshToken) }
            refreshTask = task
        }
        do {
            let fresh = try await task.value
            refreshTask = nil
            // Ignore the result if the player signed out meanwhile.
            guard session?.userID == fresh.userID else { throw OnlineError.signInRequired }
            store(fresh)
            return fresh.accessToken
        } catch OnlineError.offline {
            refreshTask = nil
            throw OnlineError.offline
        } catch {
            refreshTask = nil
            // Only a rejected refresh token means the sign-in is gone; other failures may be temporary.
            var rejected = false
            switch error as? OnlineError {
            case .signInRequired?: rejected = true
            case .server(let code, _)?: rejected = (code ?? "").contains("refresh_token") || (code ?? "").contains("session")
            default: rejected = false
            }
            if rejected && session?.refreshToken == current.refreshToken { clearSession() }
            throw rejected ? OnlineError.signInRequired : error
        }
    }

    /// Runs a request with the player's token, refreshing and retrying once if the token was rejected.
    func authorized<T>(_ work: (SupabaseClient, String) async throws -> T) async throws -> T {
        guard let client = client else { throw OnlineError.notConfigured }
        let token = try await accessToken()
        do {
            return try await work(client, token)
        } catch OnlineError.signInRequired {
            let fresh = try await accessToken(forceRefresh: true)
            return try await work(client, fresh)
        }
    }

    func refreshProfile() async {
        guard let id = session?.userID else { return }
        do {
            let data = try await authorized { client, token in
                try await client.get("profiles?id=eq.\(id)&select=username,is_admin", token: token)
            }
            struct Row: Decodable {
                let username: String
                let is_admin: Bool
            }
            if let row = try JSONDecoder().decode([Row].self, from: data).first, session?.userID == id {
                profile = Profile(username: row.username, isAdmin: row.is_admin)
                defaults.set(["user": id, "username": row.username, "admin": row.is_admin], forKey: AccountStore.profileKey)
            }
        } catch {
            // Keep whatever we knew; the next screen visit tries again.
        }
    }
}

extension SupabaseClient {
    var baseString: String { config.baseURL?.absoluteString ?? "" }
}
