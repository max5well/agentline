import Foundation

struct BackendConfig {
    static let production = URL(string: "https://agentline-chi.vercel.app")!

    var baseURL = production
    var isConfigured = true

    // Production is baked in — no setup step. Override order: demo launch
    // flag (UI tests) > Settings screen (UserDefaults) > scheme env > prod.
    static var current: BackendConfig {
        var config = BackendConfig()
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            config.isConfigured = false
            return config
        }
        let defaults = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment
        let override = defaults.string(forKey: "backend.url").flatMap { $0.isEmpty ? nil : $0 }
            ?? env["AGENTLINE_BACKEND_URL"]
        if let url = override.flatMap(URL.init(string:)) {
            config.baseURL = url
        }
        return config
    }
}

struct UsageReport: Codable {
    struct ClassUsage: Codable {
        let usedMinutes: Double
        let quotaMinutes: Double?   // nil = unlimited
    }
    let plan: String
    let creditCents: Int
    let fast: ClassUsage
    let big: ClassUsage
}

struct RealtimeToken: Codable {
    let clientSecret: String
    let expiresAt: Int
    let model: String
    let provider: String
    // Gemini only: the session is configured by the app's setup message,
    // so the backend hands the config over. OpenAI bakes it into the secret.
    let instructions: String?
    let voice: String?
}

enum AuthError: LocalizedError {
    case signedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Signed out"
        case .server(let message): message
        }
    }
}

struct BackendClient {
    var config = BackendConfig()

    // Supabase emits ISO8601 with fractional seconds; plain .iso8601 can't
    // parse those.
    static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "unparseable date: \(s)"
            ))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Requests

    private func bareRequest(_ path: String, method: String, body: Encodable?, bearer: String?) async throws -> (Data, Int) {
        var req = URLRequest(url: config.baseURL.appending(path: path))
        req.httpMethod = method
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    // Authenticated request (ADR-6): bearer token from the Keychain,
    // refreshed when expiring or on a 401, one retry, signed out when the
    // refresh token is dead too.
    private func request(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        guard var session = KeychainSession.load() else { throw AuthError.signedOut }
        if session.expiresAt.timeIntervalSinceNow < 60 {
            session = try await refresh(session)
        }

        var (data, status) = try await bareRequest(path, method: method, body: body, bearer: session.accessToken)
        if status == 401 {
            session = try await refresh(session)
            (data, status) = try await bareRequest(path, method: method, body: body, bearer: session.accessToken)
        }
        guard (200..<300).contains(status) else {
            // Surface the server's message (e.g. quota exceeded) instead of
            // a generic URL error.
            struct Failure: Codable { let error: String }
            if let message = (try? Self.decoder.decode(Failure.self, from: data))?.error {
                throw AuthError.server(message)
            }
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func refresh(_ session: AuthSession) async throws -> AuthSession {
        struct Body: Encodable { let refreshToken: String }
        let (data, status) = try await bareRequest(
            "/api/auth/refresh", method: "POST",
            body: Body(refreshToken: session.refreshToken), bearer: nil
        )
        guard (200..<300).contains(status),
              let response = try? Self.decoder.decode(SessionResponse.self, from: data) else {
            KeychainSession.clear()
            throw AuthError.signedOut
        }
        let refreshed = response.session
        KeychainSession.save(refreshed)
        return refreshed
    }

    // MARK: - Auth (no bearer; these mint the session)

    private func authRequest(_ path: String, body: Encodable) async throws -> AuthSession {
        let (data, status) = try await bareRequest(path, method: "POST", body: body, bearer: nil)
        guard (200..<300).contains(status) else {
            struct Failure: Codable { let error: String }
            let message = (try? Self.decoder.decode(Failure.self, from: data))?.error
            throw AuthError.server(message ?? "Request failed (\(status))")
        }
        return try Self.decoder.decode(SessionResponse.self, from: data).session
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        struct Body: Encodable { let email, password: String }
        return try await authRequest("/api/auth/signup", body: Body(email: email, password: password))
    }

    func logIn(email: String, password: String) async throws -> AuthSession {
        struct Body: Encodable { let email, password: String }
        return try await authRequest("/api/auth/login", body: Body(email: email, password: password))
    }

    func exchangeSSO(provider: String, idToken: String, nonce: String?) async throws -> AuthSession {
        struct Body: Encodable { let provider, idToken: String; let nonce: String? }
        return try await authRequest("/api/auth/sso", body: Body(provider: provider, idToken: idToken, nonce: nonce))
    }

    // The Supabase URL, needed for the Google web-OAuth flow.
    func supabaseURL() async throws -> URL {
        struct Config: Codable { let supabaseUrl: String? }
        let (data, status) = try await bareRequest("/api/auth/config", method: "GET", body: nil, bearer: nil)
        guard (200..<300).contains(status),
              let url = (try? Self.decoder.decode(Config.self, from: data))?.supabaseUrl.flatMap(URL.init(string:)) else {
            throw URLError(.badServerResponse)
        }
        return url
    }

    // MARK: - Data

    func agents() async throws -> [Agent] {
        struct Wrapper: Codable { let agents: [Agent] }
        let data = try await request("/api/agents")
        return try Self.decoder.decode(Wrapper.self, from: data).agents
    }

    func calls() async throws -> [CallRecord] {
        struct Wrapper: Codable { let calls: [CallRecord] }
        let data = try await request("/api/calls")
        return try Self.decoder.decode(Wrapper.self, from: data).calls
    }

    func saveAgent(_ agent: Agent) async throws {
        _ = try await request("/api/agents", method: "POST", body: agent)
    }

    func uploadAvatar(_ pngData: Data) async throws -> String {
        struct Body: Encodable { let imageBase64: String }
        struct Response: Codable { let url: String }
        let data = try await request("/api/avatar", method: "POST", body: Body(imageBase64: pngData.base64EncodedString()))
        return try Self.decoder.decode(Response.self, from: data).url
    }

    func generateAvatars(description: String) async throws -> [String] {
        struct Body: Encodable { let description: String }
        struct Response: Codable { let urls: [String] }
        let data = try await request("/api/avatar/generate", method: "POST", body: Body(description: description))
        return try Self.decoder.decode(Response.self, from: data).urls
    }

    func mcpStatus() async throws -> MCPConnection? {
        struct Wrapper: Codable { let connection: MCPConnection? }
        let data = try await request("/api/mcp")
        return try Self.decoder.decode(Wrapper.self, from: data).connection
    }

    func mcpConnect(url: String, authToken: String) async throws -> (serverName: String, tools: [MCPTool]) {
        struct Body: Encodable { let url: String; let authToken: String }
        struct Response: Codable { let serverName: String; let tools: [MCPTool] }
        let data = try await request("/api/mcp", method: "POST", body: Body(url: url, authToken: authToken))
        let r = try Self.decoder.decode(Response.self, from: data)
        return (r.serverName, r.tools)
    }

    func mcpSelectTool(_ name: String) async throws {
        struct Body: Encodable { let toolName: String }
        _ = try await request("/api/mcp", method: "PATCH", body: Body(toolName: name))
    }

    func mcpDisconnect() async throws {
        _ = try await request("/api/mcp", method: "DELETE")
    }

    func mcpPush(callId: UUID) async throws {
        struct Body: Encodable { let callId: UUID }
        _ = try await request("/api/mcp/push", method: "POST", body: Body(callId: callId))
    }

    func voicePreview(voice: String, style: String?) async throws -> Data {
        struct Body: Encodable { let voice: String; let style: String? }
        return try await request("/api/voice-preview", method: "POST", body: Body(voice: voice, style: style))
    }

    func deleteCall(id: UUID) async throws {
        _ = try await request("/api/calls?id=\(id.uuidString)", method: "DELETE")
    }

    func mintRealtimeToken(agentId: UUID) async throws -> RealtimeToken {
        struct Body: Encodable { let agentId: UUID }
        let data = try await request("/api/realtime/token", method: "POST", body: Body(agentId: agentId))
        return try Self.decoder.decode(RealtimeToken.self, from: data)
    }

    func saveCall(agentId: UUID, provider: String, model: String?, startedAt: Date, endedAt: Date, transcript: [TranscriptEntry], costCents: Int?) async throws {
        struct Body: Encodable {
            let agentId: UUID
            let provider: String
            let model: String?
            let startedAt: Date
            let endedAt: Date
            let transcript: [TranscriptEntry]
            let costCents: Int?
        }
        _ = try await request(
            "/api/calls", method: "POST",
            body: Body(agentId: agentId, provider: provider, model: model, startedAt: startedAt, endedAt: endedAt, transcript: transcript, costCents: costCents)
        )
    }

    func usage() async throws -> UsageReport {
        let data = try await request("/api/usage")
        return try Self.decoder.decode(UsageReport.self, from: data)
    }

    func addTestCredit() async throws -> Int {
        struct Response: Codable { let creditCents: Int }
        let data = try await request("/api/usage", method: "POST")
        return try Self.decoder.decode(Response.self, from: data).creditCents
    }
}
