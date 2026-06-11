import Foundation
import Security

// ADR-6: the app holds a Supabase session minted by the backend's
// /api/auth routes. The Keychain is the source of truth (BackendClient
// reads/writes it from any thread); AuthStore mirrors it for SwiftUI.

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String?
}

// What the backend's auth endpoints return.
struct SessionResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval // epoch seconds
    let userId: String
    let email: String?

    var session: AuthSession {
        AuthSession(
            accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            userId: userId, email: email
        )
    }
}

enum KeychainSession {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.max5well.Agentline",
        kSecAttrAccount as String: "auth-session",
    ]

    static func load() -> AuthSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        NotificationCenter.default.post(name: .authSessionChanged, object: nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
        NotificationCenter.default.post(name: .authSessionChanged, object: nil)
    }
}

extension Notification.Name {
    static let authSessionChanged = Notification.Name("authSessionChanged")
}

@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()
    private(set) var session: AuthSession?

    private init() {
        session = KeychainSession.load()
        NotificationCenter.default.addObserver(
            forName: .authSessionChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AuthStore.shared.session = KeychainSession.load() }
        }
    }

    func signedIn(_ session: AuthSession) {
        KeychainSession.save(session)
        self.session = session
    }

    func signOut() {
        KeychainSession.clear()
        session = nil
    }
}
