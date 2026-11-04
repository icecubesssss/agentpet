import Foundation

/// One row of the Titroutine reminder list. `startedAt != nil` marks an
/// in-progress task, drawn with a live elapsed timer like a running agent;
/// `targetMinutes` is its focus goal. Habits/todos leave both at their default.
struct TitroutineRow: Sendable, Equatable {
    let icon: String
    let title: String
    var startedAt: Date? = nil
    var targetMinutes: Int = 0
}

public struct DrawerHabitItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public var isCompleted: Bool
    public let type: String // "boolean", "counter", "timer"
    public var currentValue: Int
    public let targetCount: Int
    public let targetSeconds: Int
    public let timeOfDay: String?
    public var weeklyLogs: [Bool] // 7 days of current week (Mon..Sun)
}

public struct DrawerTaskItem: Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var notes: String?
    public var status: String // "todo", "in_progress", "done"
    public var priority: String // "low", "medium", "high"
    public var assigneeType: String // "self", "pet"
    public var focusDuration: Int
    public var deadline: String?
    public var startedAt: Date?
}

public struct DrawerProfileStats: Sendable, Equatable {
    public let streak: Int
    public let coins: Int
    public let petStage: Int
}

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

    /// Outstanding work as ready-to-render rows (in-progress tasks first, then
    /// habits, then to-do tasks).
    struct Outstanding: Sendable {
        var rows: [TitroutineRow]
        var total: Int { rows.count }
    }

    private static let refreshTokenAccount = "refreshToken"

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var currentUserId: String?

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
        currentUserId = nil
        UserDefaults.standard.removeObject(forKey: "agentpet.titroutine.currentUserId")
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
        if let uid = token.user?.id {
            currentUserId = uid
            UserDefaults.standard.set(uid, forKey: "agentpet.titroutine.currentUserId")
        }
    }

    private func fetchUserId() async throws -> String {
        if let currentUserId, !currentUserId.isEmpty {
            return currentUserId
        }
        if let stored = UserDefaults.standard.string(forKey: "agentpet.titroutine.currentUserId"), !stored.isEmpty {
            currentUserId = stored
            return stored
        }
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base.appending(path: "auth/v1/user")
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        if let userObj = try? Self.decoder.decode(UserInfo.self, from: data) {
            currentUserId = userObj.id
            UserDefaults.standard.set(userObj.id, forKey: "agentpet.titroutine.currentUserId")
            return userObj.id
        }
        throw TitroutineError.auth("Could not determine user ID")
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

    /// Fetch outstanding habits (not completed today), in-progress tasks (with
    /// their start time + focus goal, for the live timer) and to-do tasks.
    func fetchOutstanding() async throws -> Outstanding {
        let settings = TitroutineSettings.shared
        let userId = try await fetchUserId()
        var rows: [TitroutineRow] = []

        if settings.onlyInProgress {
            let active: [ActiveRow] = try await restGET(
                table: "tasks",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "id,title,updated_at,focus_duration,assignee_type,deadline"),
                        .init(name: "status", value: "eq.in_progress")])
            let filteredActive = active.filter { row in
                if !settings.includePetTasks && row.assigneeType == "pet" {
                    return false
                }
                return true
            }
            rows += filteredActive.map {
                TitroutineRow(icon: "⏱", title: $0.title,
                              startedAt: Self.parseDate($0.updatedAt),
                              targetMinutes: $0.focusDuration)
            }
            return Outstanding(rows: rows)
        }

        if settings.includeTasks {
            let active: [ActiveRow] = try await restGET(
                table: "tasks",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "id,title,updated_at,focus_duration,assignee_type,deadline"),
                        .init(name: "status", value: "eq.in_progress")])
            let todos: [TaskRow] = try await restGET(
                table: "tasks",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "id,title,assignee_type,deadline"),
                        .init(name: "status", value: "eq.todo")])

            let todayStr = Self.localToday()

            let filteredActive = active.filter { row in
                if !settings.includePetTasks && row.assigneeType == "pet" {
                    return false
                }
                if let dl = row.deadline, dl.prefix(10) < todayStr {
                    return false
                }
                return true
            }
            let filteredTodos = todos.filter { row in
                if !settings.includePetTasks && row.assigneeType == "pet" {
                    return false
                }
                if let dl = row.deadline, dl.prefix(10) < todayStr {
                    return false
                }
                return true
            }

            rows += filteredActive.map {
                TitroutineRow(icon: "⏱", title: $0.title,
                              startedAt: Self.parseDate($0.updatedAt),
                              targetMinutes: $0.focusDuration)
            }
            rows += filteredTodos.map { TitroutineRow(icon: "📋", title: $0.title) }
        }

        if settings.includeHabits {
            let habits: [Row] = try await restGET(
                table: "habits",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "id,title,frequency"),
                        .init(name: "archived_at", value: "is.null"),
                        .init(name: "type", value: "neq.negative")])
            // Today's logs, then keep the ones that are done *or* marked failed
            // on the web app — both drop off the list. `select=*` (not a column
            // list / an is_failed filter) so this still works on a database
            // without migration 14's `is_failed` column.
            let todayLogs: [LogRow] = try await restGET(
                table: "habit_logs",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "*"),
                        .init(name: "date", value: "eq.\(Self.localToday())")])

            let doneIDs = Set(todayLogs
                .filter { $0.isCompleted == true || $0.isFailed == true }
                .map(\.habitId))
            let jsWeekday = Calendar.current.component(.weekday, from: Date()) - 1

            let filteredHabits = habits.filter { habit in
                if doneIDs.contains(habit.id) {
                    return false
                }
                if let freq = habit.frequency {
                    if freq.type == "specific_days", let days = freq.days {
                        return days.contains(jsWeekday)
                    }
                }
                return true
            }

            rows += filteredHabits.map { TitroutineRow(icon: "🔁", title: $0.title) }
        }

        return Outstanding(rows: rows)
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

    /// One PostgREST POST with a JSON body, decoding the created object.
    private func restPOST<B: Encodable, T: Decodable>(table: String, body: B, retrying: Bool = true) async throws -> T {
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base.appending(path: "rest/v1/\(table)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try Self.encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retrying {
            accessTokenExpiry = nil
            return try await restPOST(table: table, body: body, retrying: false)
        }
        guard (200..<300).contains(code) else { throw TitroutineError.server(code) }
        guard let item = try? Self.decoder.decode([T].self, from: data).first else { throw TitroutineError.decode }
        return item
    }

    /// One PostgREST Upsert using `resolution=merge-duplicates`.
    private func restUpsert<B: Encodable>(table: String, onConflict: String, body: B, retrying: Bool = true) async throws {
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base.appending(path: "rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: "on_conflict", value: onConflict)])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try Self.encoder.encode(body)

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retrying {
            accessTokenExpiry = nil
            return try await restUpsert(table: table, onConflict: onConflict, body: body, retrying: false)
        }
        guard (200..<300).contains(code) else { throw TitroutineError.server(code) }
    }

    /// One PostgREST PATCH with JSON body.
    private func restPATCH<B: Encodable>(table: String, query: [URLQueryItem], body: B, retrying: Bool = true) async throws {
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base.appending(path: "rest/v1/\(table)").appending(queryItems: query)
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Self.encoder.encode(body)

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retrying {
            accessTokenExpiry = nil
            return try await restPATCH(table: table, query: query, body: body, retrying: false)
        }
        guard (200..<300).contains(code) else { throw TitroutineError.server(code) }
    }

    /// One PostgREST DELETE with query.
    private func restDELETE(table: String, query: [URLQueryItem], retrying: Bool = true) async throws {
        let (base, anonKey) = try config()
        let token = try await validAccessToken()
        let url = base.appending(path: "rest/v1/\(table)").appending(queryItems: query)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retrying {
            accessTokenExpiry = nil
            return try await restDELETE(table: table, query: query, retrying: false)
        }
        guard (200..<300).contains(code) else { throw TitroutineError.server(code) }
    }

    // MARK: - Edge Drawer API Mutations & Queries

    /// Create a new task in Titroutine
    func createTask(
        title: String,
        notes: String? = nil,
        priority: String = "medium",
        assigneeType: String = "self",
        focusDuration: Int = 25,
        deadline: String? = nil
    ) async throws -> DrawerTaskItem {
        let userId = try await fetchUserId()
        struct InsertTaskBody: Encodable {
            let userId: String
            let title: String
            let notes: String?
            let priority: String
            let assigneeType: String
            let focusDuration: Int
            let deadline: String?
            let status: String
        }
        let body = InsertTaskBody(
            userId: userId,
            title: title,
            notes: notes,
            priority: priority,
            assigneeType: assigneeType,
            focusDuration: focusDuration,
            deadline: deadline,
            status: "todo"
        )
        let created: TaskRow = try await restPOST(table: "tasks", body: body)
        return DrawerTaskItem(
            id: created.id,
            title: created.title,
            notes: notes,
            status: "todo",
            priority: priority,
            assigneeType: assigneeType,
            focusDuration: focusDuration,
            deadline: deadline,
            startedAt: nil
        )
    }

    /// Update status of a task ("todo", "in_progress", "done")
    func updateTaskStatus(taskId: String, status: String) async throws {
        let userId = try await fetchUserId()
        struct PatchStatus: Encodable {
            let status: String
            let updatedAt: String
        }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        if status == "in_progress" {
            // Revert other in_progress tasks back to todo
            try? await restPATCH(
                table: "tasks",
                query: [.init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "status", value: "eq.in_progress"),
                        .init(name: "id", value: "neq.\(taskId)")],
                body: PatchStatus(status: "todo", updatedAt: nowISO)
            )
        }
        try await restPATCH(
            table: "tasks",
            query: [.init(name: "id", value: "eq.\(taskId)"),
                    .init(name: "user_id", value: "eq.\(userId)")],
            body: PatchStatus(status: status, updatedAt: nowISO)
        )

        if status == "done" {
            // Reward focus tokens and carrot in background
            Task {
                struct TaskDurationRow: Decodable { let focusDuration: Int? }
                let rows: [TaskDurationRow] = (try? await restGET(
                    table: "tasks",
                    query: [.init(name: "id", value: "eq.\(taskId)"), .init(name: "select", value: "focus_duration")]
                )) ?? []
                let duration = rows.first?.focusDuration ?? 25

                struct ProfileTokensRow: Decodable { let focusTokens: Int? }
                if let p: [ProfileTokensRow] = try? await restGET(
                    table: "profiles",
                    query: [.init(name: "id", value: "eq.\(userId)"), .init(name: "select", value: "focus_tokens")]
                ), let currentTokens = p.first?.focusTokens {
                    struct PatchTokens: Encodable { let focusTokens: Int }
                    try? await restPATCH(
                        table: "profiles",
                        query: [.init(name: "id", value: "eq.\(userId)")],
                        body: PatchTokens(focusTokens: currentTokens + duration)
                    )
                }

                struct InvConsumablesRow: Decodable { let consumables: [String: Int]? }
                if let inv: [InvConsumablesRow] = try? await restGET(
                    table: "inventory",
                    query: [.init(name: "user_id", value: "eq.\(userId)"), .init(name: "select", value: "consumables")]
                ), var cons = inv.first?.consumables {
                    cons["carrot"] = (cons["carrot"] ?? 0) + 1
                    struct PatchInv: Encodable { let consumables: [String: Int] }
                    try? await restPATCH(
                        table: "inventory",
                        query: [.init(name: "user_id", value: "eq.\(userId)")],
                        body: PatchInv(consumables: cons)
                    )
                }
            }
        }
    }

    /// Delete a task
    func deleteTask(taskId: String) async throws {
        let userId = try await fetchUserId()
        try await restDELETE(
            table: "tasks",
            query: [.init(name: "id", value: "eq.\(taskId)"),
                    .init(name: "user_id", value: "eq.\(userId)")]
        )
    }

    /// Toggle a habit's completion status for today or a specific retroactive date
    func toggleHabit(habitId: String, date: String? = nil, willComplete: Bool) async throws {
        let userId = try await fetchUserId()
        struct UpsertLog: Encodable {
            let habitId: String
            let userId: String
            let date: String
            let isCompleted: Bool
        }
        let targetDate = date ?? Self.localToday()
        let body = UpsertLog(
            habitId: habitId,
            userId: userId,
            date: targetDate,
            isCompleted: willComplete
        )
        try await restUpsert(table: "habit_logs", onConflict: "habit_id,date", body: body)
    }

    /// Fetch all completed dates for a specific habit in a given year-month ("YYYY-MM")
    func fetchHabitMonthLogs(habitId: String, monthKey: String) async throws -> Set<String> {
        let userId = try await fetchUserId()
        let startDate = "\(monthKey)-01"
        let endDate = "\(monthKey)-31"
        let logs: [LogRow] = (try? await restGET(
            table: "habit_logs",
            query: [
                .init(name: "user_id", value: "eq.\(userId)"),
                .init(name: "habit_id", value: "eq.\(habitId)"),
                .init(name: "select", value: "date,is_completed"),
                .init(name: "date", value: "gte.\(startDate)"),
                .init(name: "date", value: "lte.\(endDate)")
            ]
        )) ?? []
        let completed = logs.compactMap { log -> String? in
            guard log.isCompleted == true, let d = log.date else { return nil }
            return d
        }
        return Set(completed)
    }

    /// Increment or decrement a counter habit (e.g. drinking water, reading pages)
    func incrementCounterHabit(habitId: String, delta: Int, targetCount: Int) async throws {
        let userId = try await fetchUserId()
        let today = Self.localToday()

        let logs: [LogRow] = (try? await restGET(
            table: "habit_logs",
            query: [.init(name: "user_id", value: "eq.\(userId)"),
                    .init(name: "habit_id", value: "eq.\(habitId)"),
                    .init(name: "date", value: "eq.\(today)")]
        )) ?? []

        let currentVal = logs.first?.value ?? 0
        let newVal = max(0, currentVal + delta)
        let willComplete = newVal >= targetCount

        struct UpsertCounterLog: Encodable {
            let habitId: String
            let userId: String
            let date: String
            let isCompleted: Bool
            let value: Int
        }
        let body = UpsertCounterLog(
            habitId: habitId,
            userId: userId,
            date: today,
            isCompleted: willComplete,
            value: newVal
        )
        try await restUpsert(table: "habit_logs", onConflict: "habit_id,date", body: body)
    }

    /// Create a new habit from the Drawer
    func createHabit(
        title: String,
        type: String = "boolean",
        targetCount: Int = 1,
        durationMinutes: Int = 20,
        timeOfDay: String = "anytime"
    ) async throws {
        let userId = try await fetchUserId()
        var config: [String: AnyCodable] = [:]
        if type == "counter" {
            config["target_count"] = AnyCodable(targetCount)
        } else if type == "timer" {
            config["target_time"] = AnyCodable(durationMinutes * 60)
        }

        struct InsertHabitBody: Encodable {
            let userId: String
            let title: String
            let type: String
            let config: [String: AnyCodable]
            let timeOfDay: String
        }
        let body = InsertHabitBody(
            userId: userId,
            title: title,
            type: type,
            config: config,
            timeOfDay: timeOfDay
        )
        struct CreatedHabitRow: Decodable { let id: String }
        let _: CreatedHabitRow = try await restPOST(table: "habits", body: body)
    }

    /// Fetch all habits with completion status, counter values, and weekly streak dots
    func fetchDrawerHabits() async throws -> [DrawerHabitItem] {
        let userId = try await fetchUserId()
        let habits: [HabitDetailRow] = try await restGET(
            table: "habits",
            query: [.init(name: "user_id", value: "eq.\(userId)"),
                    .init(name: "select", value: "id,title,type,config,frequency,time_of_day"),
                    .init(name: "archived_at", value: "is.null"),
                    .init(name: "type", value: "neq.negative")]
        )
        let weekDates = Self.currentWeekDates()
        let minDate = weekDates.first ?? Self.localToday()
        let maxDate = weekDates.last ?? Self.localToday()

        let logs: [LogRow] = (try? await restGET(
            table: "habit_logs",
            query: [.init(name: "user_id", value: "eq.\(userId)"),
                    .init(name: "select", value: "habit_id,date,is_completed,value"),
                    .init(name: "date", value: "gte.\(minDate)"),
                    .init(name: "date", value: "lte.\(maxDate)")]
        )) ?? []

        let today = Self.localToday()
        let jsWeekday = Calendar.current.component(.weekday, from: Date()) - 1

        return habits.compactMap { h in
            if let freq = h.frequency, freq.type == "specific_days", let days = freq.days {
                if !days.contains(jsWeekday) { return nil }
            }
            let todayLog = logs.first(where: { $0.habitId == h.id && $0.date == today })
            let isCompleted = todayLog?.isCompleted == true
            let currentVal = todayLog?.value ?? 0
            let habitType = h.type ?? "boolean"

            var targetCount = 1
            var targetSeconds = 25 * 60
            if let cfg = h.config {
                if let tc = cfg["target_count"]?.value as? Int { targetCount = tc }
                if let tt = cfg["target_time"]?.value as? Int { targetSeconds = tt }
            }

            let weeklyLogs = weekDates.map { date in
                logs.contains { $0.habitId == h.id && $0.date == date && $0.isCompleted == true }
            }

            return DrawerHabitItem(
                id: h.id,
                title: h.title,
                isCompleted: isCompleted,
                type: habitType,
                currentValue: currentVal,
                targetCount: targetCount,
                targetSeconds: targetSeconds,
                timeOfDay: h.timeOfDay,
                weeklyLogs: weeklyLogs
            )
        }
    }

    /// Fetch tasks for the Drawer
    func fetchDrawerTasks() async throws -> [DrawerTaskItem] {
        let userId = try await fetchUserId()
        let rows: [TaskDetailRow] = try await restGET(
            table: "tasks",
            query: [.init(name: "user_id", value: "eq.\(userId)"),
                    .init(name: "select", value: "id,title,notes,status,priority,assignee_type,focus_duration,deadline,updated_at"),
                    .init(name: "order", value: "created_at.desc")]
        )
        return rows.map { r in
            DrawerTaskItem(
                id: r.id,
                title: r.title,
                notes: r.notes,
                status: r.status,
                priority: r.priority ?? "medium",
                assigneeType: r.assigneeType ?? "self",
                focusDuration: r.focusDuration ?? 25,
                deadline: r.deadline,
                startedAt: r.status == "in_progress" ? Self.parseDate(r.updatedAt ?? "") : nil
            )
        }
    }

    /// Fetch user profile summary (streak, coins)
    func fetchProfileStats() async throws -> DrawerProfileStats {
        let userId = try await fetchUserId()
        struct ProfileRow: Decodable {
            let currentStreak: Int?
            let coins: Int?
            let petStage: Int?
        }
        let profiles: [ProfileRow] = try await restGET(
            table: "profiles",
            query: [.init(name: "id", value: "eq.\(userId)"),
                    .init(name: "select", value: "current_streak,coins,pet_stage")]
        )
        let p = profiles.first
        return DrawerProfileStats(
            streak: p?.currentStreak ?? 0,
            coins: p?.coins ?? 0,
            petStage: p?.petStage ?? 0
        )
    }

    /// Save quick notes into user's profile preferences
    func saveQuickNotes(notes: String) async throws {
        let userId = try await fetchUserId()
        struct PrefsRow: Decodable {
            let preferences: [String: AnyCodable]?
        }
        let rows: [PrefsRow] = try await restGET(
            table: "profiles",
            query: [.init(name: "id", value: "eq.\(userId)"),
                    .init(name: "select", value: "preferences")]
        )
        var dict: [String: AnyCodable] = rows.first?.preferences ?? [:]
        dict["quick_notes"] = AnyCodable(notes)

        struct PatchPrefs: Encodable {
            let preferences: [String: AnyCodable]
        }
        try await restPATCH(
            table: "profiles",
            query: [.init(name: "id", value: "eq.\(userId)")],
            body: PatchPrefs(preferences: dict)
        )
    }

    // MARK: - Wire types

    private struct UserInfo: Decodable {
        let id: String
        let email: String?
    }
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: UserInfo?
    }
    private struct HabitFrequency: Decodable {
        let type: String
        let days: [Int]?
    }
    private struct Row: Decodable {
        let id: String
        let title: String
        let frequency: HabitFrequency?
    }
    private struct TaskRow: Decodable {
        let id: String
        let title: String
        let assigneeType: String?
        let deadline: String?
    }
    private struct LogRow: Decodable {
        let habitId: String
        let date: String?
        let isCompleted: Bool?
        let isFailed: Bool?
        let value: Int?
    }
    private struct ActiveRow: Decodable {
        let id: String
        let title: String
        let updatedAt: String      // ISO8601; used as the "started" mark
        let focusDuration: Int
        let assigneeType: String?
        let deadline: String?
    }
    private struct HabitDetailRow: Decodable {
        let id: String
        let title: String
        let type: String?
        let config: [String: AnyCodable]?
        let frequency: HabitFrequency?
        let timeOfDay: String?
    }
    private struct TaskDetailRow: Decodable {
        let id: String
        let title: String
        let notes: String?
        let status: String
        let priority: String?
        let assigneeType: String?
        let focusDuration: Int?
        let deadline: String?
        let updatedAt: String?
    }

    private static func currentWeekDates() -> [String] {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return (0..<7).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: monday) else { return nil }
            return f.string(from: d)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

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

    private static func localYesterday() -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return f.string(from: yesterday)
    }

    /// Parse a Postgres timestamptz (with or without fractional seconds).
    private static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { self.value = b }
        else if let i = try? container.decode(Int.self) { self.value = i }
        else if let d = try? container.decode(Double.self) { self.value = d }
        else if let s = try? container.decode(String.self) { self.value = s }
        else if let arr = try? container.decode([AnyCodable].self) { self.value = arr.map(\.value) }
        else if let dict = try? container.decode([String: AnyCodable].self) { self.value = dict.mapValues(\.value) }
        else { self.value = "" }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let b = value as? Bool { try container.encode(b) }
        else if let i = value as? Int { try container.encode(i) }
        else if let d = value as? Double { try container.encode(d) }
        else if let s = value as? String { try container.encode(s) }
        else if let arr = value as? [Any] { try container.encode(arr.map { AnyCodable($0) }) }
        else if let dict = value as? [String: Any] { try container.encode(dict.mapValues { AnyCodable($0) }) }
        else { try container.encodeNil() }
    }
}
