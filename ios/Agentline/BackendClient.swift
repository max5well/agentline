import Foundation

struct BackendConfig {
    // Filled from Config.xcconfig / scheme env later; placeholder for now.
    var baseURL = URL(string: "http://localhost:3000")!
    var appSecret = ""
}

struct RealtimeToken: Codable {
    let clientSecret: String
    let expiresAt: Int
    let model: String
    let provider: String
}

struct BackendClient {
    var config = BackendConfig()

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: config.baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue(config.appSecret, forHTTPHeaderField: "x-app-secret")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
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
        return try JSONDecoder().decode(Wrapper.self, from: data).agents
    }

    func mintRealtimeToken(agentId: UUID) async throws -> RealtimeToken {
        struct Body: Encodable { let agentId: UUID }
        let data = try await request("/api/realtime/token", method: "POST", body: Body(agentId: agentId))
        return try JSONDecoder().decode(RealtimeToken.self, from: data)
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
