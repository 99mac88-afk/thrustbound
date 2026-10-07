import Foundation
import Security

/// Where the community server lives (a Supabase project).
struct BackendConfig: Codable, Equatable {
    var url: String
    var anonKey: String

    /// The project URL without a trailing slash, or nil if it isn't usable.
    var baseURL: URL? {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let u = URL(string: text), u.scheme?.lowercased() == "https", u.host != nil else { return nil }
        return u
    }

    var isUsable: Bool {
        baseURL != nil && !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Resources/backend.json, filled in by the release build when the repo has the secrets.
    static func bundled(_ bundle: Bundle = .main) -> BackendConfig? {
        guard let file = bundle.url(forResource: "backend", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(BackendConfig.self, from: data),
              config.isUsable else { return nil }
        return config
    }
}

enum OnlineError: Error, Equatable {
    case notConfigured
    case offline
    case signInRequired
    case confirmEmail
    case usernameTaken
    case badUsername
    case badLevel
    case notAllowed
    case server(code: String?, message: String)
}

/// A signed-in account's tokens.
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
    /// Which server these tokens belong to.
    var server: String
}

/// Thin client for the two Supabase APIs the game uses: Auth (accounts) and PostgREST (tables).
struct SupabaseClient {
    let config: BackendConfig
    private let base: URL

    init?(_ config: BackendConfig) {
        guard let base = config.baseURL, config.isUsable else { return nil }
        self.config = config
        self.base = base
    }

    private var key: String { config.anonKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send(_ method: String, _ path: String, json: Any? = nil, body: Data? = nil,
                      token: String?, prefer: String? = nil) async throws -> (Data, Int) {
        guard let url = URL(string: base.absoluteString + path) else { throw OnlineError.badLevel }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        // Signed-out requests send only the public key (works with both anon and publishable keys).
        if let token = token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer = prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let json = json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OnlineError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SupabaseClient.error(from: data, status: status) }
        return (data, status)
    }

    /// Auth errors look like {"error_code","msg"}; table errors like {"code","message"}.
    static func error(from data: Data, status: Int) -> OnlineError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (object["error_code"] as? String) ?? (object["code"] as? String) ?? (object["error"] as? String)
        let message = (object["msg"] as? String) ?? (object["message"] as? String)
            ?? (object["error_description"] as? String) ?? (object["error"] as? String) ?? "HTTP \(status)"
        if message.localizedCaseInsensitiveContains("username is already taken") { return .usernameTaken }
        if message.hasPrefix("Username must be") { return .badUsername }
        if code == "42501" || message.contains("permission denied") { return status == 401 ? .signInRequired : .notAllowed }
        if status == 401 || code == "PGRST301" || message.localizedCaseInsensitiveContains("JWT expired") {
            return .signInRequired
        }
        return .server(code: code, message: message)
    }

    // MARK: - Auth

    private func session(from data: Data) -> AuthSession? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = o["access_token"] as? String,
              let refresh = o["refresh_token"] as? String,
              let user = o["user"] as? [String: Any],
              let id = user["id"] as? String else { return nil }
        let expiresIn = (o["expires_in"] as? Double) ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn),
                           userID: id, email: user["email"] as? String, server: base.absoluteString)
    }

    /// Returns nil when the project still asks new accounts to confirm their email.
    func signUp(email: String, password: String, username: String) async throws -> AuthSession? {
        let (data, _) = try await send("POST", "/auth/v1/signup",
                                       json: ["email": email, "password": password, "data": ["username": username]],
                                       token: nil)
        return session(from: data)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let (data, _) = try await send("POST", "/auth/v1/token?grant_type=password",
                                       json: ["email": email, "password": password], token: nil)
        guard let s = session(from: data) else { throw OnlineError.server(code: nil, message: "Unexpected reply") }
        return s
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let (data, _) = try await send("POST", "/auth/v1/token?grant_type=refresh_token",
                                       json: ["refresh_token": refreshToken], token: nil)
        guard let s = session(from: data) else { throw OnlineError.signInRequired }
        return s
    }

    func signOut(token: String) async {
        _ = try? await send("POST", "/auth/v1/logout", json: [String: String](), token: token)
    }

    // MARK: - Tables and functions

    func get(_ pathAndQuery: String, token: String?) async throws -> Data {
        try await send("GET", "/rest/v1/" + pathAndQuery, token: token).0
    }

    func insert(_ table: String, body: Data, token: String) async throws -> Data {
        try await send("POST", "/rest/v1/" + table, body: body, token: token, prefer: "return=representation").0
    }

    func delete(_ table: String, filter: String, token: String) async throws -> Data {
        try await send("DELETE", "/rest/v1/\(table)?\(filter)", token: token, prefer: "return=representation").0
    }

    func rpc(_ name: String, _ args: [String: Any], token: String?) async throws -> Data {
        try await send("POST", "/rest/v1/rpc/" + name, json: args, token: token).0
    }

    func usernameAvailable(_ name: String) async throws -> Bool {
        let data = try await rpc("username_available", ["p_name": name], token: nil)
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }
}

/// Keeps the session tokens in the Keychain (falls back to app storage if the Keychain refuses).
enum SecureStore {
    private static let service = "com.thrustbound.account"
    private static let fallbackKey = "account.session.fallback"

    static func save(_ data: Data, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey + account)
        } else {
            UserDefaults.standard.set(data, forKey: fallbackKey + account)
        }
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return data
        }
        return UserDefaults.standard.data(forKey: fallbackKey + account)
    }

    static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey + account)
    }
}
