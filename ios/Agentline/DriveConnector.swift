import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

// Google Drive export via client-side OAuth (PKCE — iOS clients have no
// secret). Tokens never touch our backend; refresh token lives in the
// Keychain. Needs a Google Cloud OAuth client ID (iOS type), pasted once
// in the connect sheet.
enum DriveConnector {
    private static let scope = "https://www.googleapis.com/auth/drive.file"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "drive.clientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "drive.clientID") }
    }

    // Reversed client id is Google's required redirect scheme for iOS.
    private static var redirectScheme: String? {
        let parts = clientID.split(separator: ".")
        guard parts.count > 1, clientID.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var isConnected: Bool { KeychainDriveToken.load() != nil }

    static func disconnect() { KeychainDriveToken.clear() }

    // MARK: - OAuth (authorization code + PKCE)

    @MainActor
    static func connect(webSession: WebAuthenticationSession) async throws {
        guard let scheme = redirectScheme else {
            throw AuthError.server("Enter a valid iOS OAuth client ID first (ends in .apps.googleusercontent.com)")
        }
        let verifier = randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let redirectURI = "\(scheme):/oauth2redirect"

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let callback = try await webSession.authenticate(
            using: auth.url!,
            callbackURLScheme: scheme,
            preferredBrowserSession: .shared
        )
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.server("Google returned no authorization code")
        }

        let token = try await exchange(form: [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
        KeychainDriveToken.save(token)
    }

    private static func freshAccessToken() async throws -> String {
        guard var token = KeychainDriveToken.load() else { throw AuthError.signedOut }
        if token.expiresAt.timeIntervalSinceNow > 60 { return token.accessToken }
        let refreshed = try await exchange(form: [
            "client_id": clientID,
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token",
        ])
        token = DriveToken(
            accessToken: refreshed.accessToken,
            refreshToken: token.refreshToken,   // refresh grants omit it
            expiresAt: refreshed.expiresAt
        )
        KeychainDriveToken.save(token)
        return token.accessToken
    }

    private static func exchange(form: [String: String]) async throws -> DriveToken {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.server("Google token exchange failed: \(body.prefix(140))")
        }
        struct Response: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        return DriveToken(
            accessToken: parsed.access_token,
            refreshToken: parsed.refresh_token ?? "",
            expiresAt: Date().addingTimeInterval(parsed.expires_in)
        )
    }

    // MARK: - Export

    static func export(record: CallRecord, agent: Agent, includeTranscript: Bool) async throws {
        let accessToken = try await freshAccessToken()

        var md = "# Call with \(agent.name)\n\n"
        md += "_\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationLabel)_\n\n"
        if let summary = record.summary { md += "## Summary\n\(summary)\n\n" }
        if let intents = record.intents, !intents.isEmpty {
            md += "## Action items\n" + intents.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if includeTranscript, !record.transcript.isEmpty {
            md += "## Transcript\n"
            md += record.transcript.map { "**\($0.role == "user" ? "Max" : agent.name):** \($0.text)" }.joined(separator: "\n")
        }

        let metadata: [String: Any] = [
            "name": "Call with \(agent.name) — \(record.startedAt.formatted(.dateTime.year().month().day().hour().minute())).md",
            "mimeType": "text/markdown",
        ]
        let boundary = "agentline-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append("\r\n--\(boundary)\r\nContent-Type: text/markdown\r\n\r\n".data(using: .utf8)!)
        body.append(md.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.server("Drive upload failed: \(message.prefix(140))")
        }
    }

    private static func randomURLSafe(_ length: Int) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in charset.randomElement()! })
    }
}

struct DriveToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum KeychainDriveToken {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.max5well.Agentline",
        kSecAttrAccount as String: "drive-token",
    ]

    static func load() -> DriveToken? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(DriveToken.self, from: data)
    }

    static func save(_ token: DriveToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        var add = query
        add[kSecValueData as String] = data
        if SecItemAdd(add as CFDictionary, nil) == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    static func clear() { SecItemDelete(query as CFDictionary) }
}
