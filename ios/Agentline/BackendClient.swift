import Foundation

struct BackendConfig {
    var baseURL = URL(string: "http://localhost:3000")!
    var appSecret = ""

    var isConfigured: Bool { !appSecret.isEmpty }

    // Settings screen (UserDefaults) wins; scheme environment is the
    // dev fallback — scheme edits don't survive xcodegen regeneration.
    static var current: BackendConfig {
        let defaults = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment
        var config = BackendConfig()
        let urlString = defaults.string(forKey: "backend.url").flatMap { $0.isEmpty ? nil : $0 }
            ?? env["AGENTLINE_BACKEND_URL"]
        if let url = urlString.flatMap(URL.init(string:)) {
            config.baseURL = url
        }
        config.appSecret = defaults.string(forKey: "backend.secret").flatMap { $0.isEmpty ? nil : $0 }
            ?? env["AGENTLINE_APP_SECRET"] ?? ""
        return config
    }
}

struct RealtimeToken: Codable {
    let clientSecret: String
    let expiresAt: Int
    let model: String
    let provider: String
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

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: config.baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue(config.appSecret, forHTTPHeaderField: "x-app-secret")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

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

    func mintRealtimeToken(agentId: UUID) async throws -> RealtimeToken {
        struct Body: Encodable { let agentId: UUID }
        let data = try await request("/api/realtime/token", method: "POST", body: Body(agentId: agentId))
        return try Self.decoder.decode(RealtimeToken.self, from: data)
    }

    func saveCall(agentId: UUID, provider: String, startedAt: Date, endedAt: Date, transcript: [TranscriptEntry], costCents: Int?) async throws {
        struct Body: Encodable {
            let agentId: UUID
            let provider: String
            let startedAt: Date
            let endedAt: Date
            let transcript: [TranscriptEntry]
            let costCents: Int?
        }
        _ = try await request(
            "/api/calls", method: "POST",
            body: Body(agentId: agentId, provider: provider, startedAt: startedAt, endedAt: endedAt, transcript: transcript, costCents: costCents)
        )
    }
}
