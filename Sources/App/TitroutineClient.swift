import Foundation

/// Talks to Titroutine's Supabase directly (GoTrue auth + PostgREST), so no
/// changes are needed on the web side. Sign in once with the Titroutine
/// email/password; the refresh token is kept in the Keychain and access tokens
/// are minted on demand. RLS scopes every read to the signed-in user.
@MainActor
final class TitroutineClient: ObservableObject {
    static let shared = TitroutineClient()

    enum TitroutineError: LocalizedError {
        case notConfigured
        case notConnected
        case auth(String)
        case server(Int)
        case decode

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Enter your Supabase URL and anon key first."
            case .notConnected: return "Not connected to Titroutine."
            case .auth(let m): return m
            case .server(let c): return "Server error (\(c))."
            case .decode: return "Unexpected response."
            }
        }
    }

    /// Outstanding work, titles only (for the reminder body).
    struct Outstanding: Sendable {
        var habitTitles: [String]
        var taskTitles: [String]
        var total: Int { habitTitles.count + taskTitles.count }
    }

    private static let refreshTokenAccount = "refreshToken"

    private var accessToken: String?
    private var accessTokenExpiry: Date?

    var isConnected: Bool { Keychain.get(Self.refreshTokenAccount) != nil }

    // MARK: - Auth

    /// Exchange email/password for tokens (Supabase password grant). Persists the
    /// refresh token and records the email in `TitroutineSettings`.
    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        var req = try authRequest(grant: "password")
        req.httpBody = body
        let token = try await runToken(req)
        Keychain.set(token.refreshToken, for: Self.refreshTokenAccount)
        store(token)
        TitroutineSettings.shared.connectedEmail = email
    }

    func signOut() {
        Keychain.set(nil, for: Self.refreshTokenAccount)
        accessToken = nil
        accessTokenExpiry = nil
        TitroutineSettings.shared.connectedEmail = nil
    }

    /// A valid access token, refreshing via the stored refresh token if the
    /// in-memory one is missing or within 60s of expiry.
    private func validAccessToken() async throws -> String {
        if let accessToken, let exp = accessTokenExpiry, exp.timeIntervalSinceNow > 60 {
            return accessToken
        }
        guard let refresh = Keychain.get(Self.refreshTokenAccount) else { throw TitroutineError.notConnected }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        var req = try authRequest(grant: "refresh_token")
        req.httpBody = body
        let token = try await runToken(req)
        Keychain.set(token.refreshToken, for: Self.refreshTokenAccount)   // rotates
        store(token)
        return token.accessToken
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
    }

    /// Base URL + anon key come from `TitroutineSettings` (user-entered), so no
    /// project-specific config lives in source.
    private func config() throws -> (base: URL, anonKey: String) {
        let s = TitroutineSettings.shared
        guard let base = s.baseURL, !s.anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw TitroutineError.notConfigured }
        return (base, s.anonKey)
    }

    private func authRequest(grant: String) throws -> URLRequest {
        let (base, anonKey) = try config()
        let url = base
            .appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: grant)])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func runToken(_ req: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // GoTrue returns { error_description | msg | error } on failure.
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["error_description"] ?? obj?["msg"] ?? obj?["error"]) as? String
            throw TitroutineError.auth(msg ?? "Sign-in failed (\(code)).")
        }
        guard let token = try? Self.decoder.decode(TokenResponse.self, from: data) else {
            throw TitroutineError.decode
        }
        return token
    }

    // MARK: - Data (habits + tasks not yet done)

    /// Fetch outstanding habits (not completed today) and tasks (status != done).
    func fetchOutstanding() async throws -> Outstanding {
        let habits: [Row] = try await restGET(
            table: "habits",
            query: [.init(name: "select", value: "id,title"),
                    .init(name: "archived_at", value: "is.null"),
                    .init(name: "type", value: "neq.negative")])
        let doneLogs: [LogRow] = try await restGET(
            table: "habit_logs",
            query: [.init(name: "select", value: "habit_id"),
                    .init(name: "date", value: "eq.\(Self.localToday())"),
                    .init(name: "is_completed", value: "eq.true")])
        let tasks: [Row] = try await restGET(
            table: "tasks",
            query: [.init(name: "select", value: "id,title"),
                    .init(name: "status", value: "neq.done")])

        let doneIDs = Set(doneLogs.map(\.habitId))
        let habitTitles = habits.filter { !doneIDs.contains($0.id) }.map(\.title)
        return Outstanding(habitTitles: habitTitles, taskTitles: tasks.map(\.title))
    }

    /// One PostgREST GET, decoding an array of `T`. Retries once after a token
    /// refresh on 401 (expired access token).
    private func restGET<T: Decodable>(table: String, query: [URLQueryItem], retrying: Bool = true) async throws -> [T] {
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base
            .appending(path: "rest/v1/\(table)")
            .appending(queryItems: query)
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retrying {
            accessTokenExpiry = nil   // force a refresh
            return try await restGET(table: table, query: query, retrying: false)
        }
        guard (200..<300).contains(code) else { throw TitroutineError.server(code) }
        guard let rows = try? Self.decoder.decode([T].self, from: data) else { throw TitroutineError.decode }
        return rows
    }

    // MARK: - Wire types

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }
    private struct Row: Decodable { let id: String; let title: String }
    private struct LogRow: Decodable { let habitId: String }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func localToday() -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
