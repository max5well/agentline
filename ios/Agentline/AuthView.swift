import AuthenticationServices
import CryptoKit
import SwiftUI

// Sign-in gate (ADR-6): email + password against the backend's auth
// routes, native Sign in with Apple (id_token exchange), and Google via
// the system web-auth session against Supabase's authorize endpoint.
struct AuthView: View {
    @Environment(\.webAuthenticationSession) private var webSession
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var appleNonce = ""

    private var backend: BackendClient { BackendClient(config: BackendConfig.current) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                wordmark
                    .padding(.top, 70)
                    .padding(.bottom, 6)
                Text(creatingAccount ? "Create your account" : "Welcome back")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 34)

                emailForm

                if let successMessage {
                    Text(successMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.green)
                        .padding(.top, 14)
                        .padding(.horizontal, 8)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                        .padding(.top, 14)
                        .padding(.horizontal, 8)
                }

                primaryButton
                    .padding(.top, 20)

                Button {
                    creatingAccount.toggle()
                    errorMessage = nil
                } label: {
                    Text(creatingAccount ? "Already have an account? Sign in" : "New here? Create an account")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 16)

                if !creatingAccount {
                    Button("Forgot password?") {
                        Task { await resetPassword() }
                    }
                    .font(.footnote)
                    .padding(.top, 12)
                }

                divider
                    .padding(.vertical, 26)

                ssoButtons
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
    }

    private var wordmark: some View {
        (Text("agent").foregroundStyle(.primary) + Text("line").foregroundStyle(Color.accentColor))
            .font(.system(size: 40, weight: .bold))
            .kerning(-1.4)
    }

    private var emailForm: some View {
        VStack(spacing: 0) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .padding(.horizontal, 16)
                .frame(height: 54)
            Divider()
            SecureField("Password", text: $password)
                .textContentType(creatingAccount ? .newPassword : .password)
                .padding(.horizontal, 16)
                .frame(height: 54)
        }
        .font(.system(size: 16))
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var primaryButton: some View {
        Button {
            Task { await submitEmail() }
        } label: {
            Text(creatingAccount ? "Create account" : "Sign in")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
        }
        .buttonStyle(.borderedProminent)
        .disabled(email.isEmpty || password.isEmpty)
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
    }

    private var ssoButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                appleNonce = Self.randomNonce()
                request.requestedScopes = [.email]
                request.nonce = Self.sha256(appleNonce)
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20))
                    Text("Continue with Google")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Flows

    private func submitEmail() async {
        busy = true
        errorMessage = nil
        do {
            if creatingAccount {
                switch try await backend.signUp(email: email, password: password) {
                case .session(let session):
                    AuthStore.shared.signedIn(session)
                case .confirmationRequired(let address):
                    successMessage = "Check \(address) to verify your email, then return here to sign in."
                    password = ""
                }
            } else {
                AuthStore.shared.signedIn(try await backend.logIn(email: email, password: password))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }


    private func resetPassword() async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email first."
            return
        }
        busy = true
        errorMessage = nil
        do {
            try await backend.requestPasswordReset(email: email)
            successMessage = "If that account exists, a password-reset email is on its way."
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // Treat user cancellation silently.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple did not return an identity token"
                return
            }
            busy = true
            errorMessage = nil
            do {
                let session = try await backend.exchangeSSO(provider: "apple", idToken: idToken, nonce: appleNonce)
                AuthStore.shared.signedIn(session)
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }

    // Google runs Supabase's hosted OAuth flow in the system browser and
    // returns the session in the callback URL fragment.
    private func signInWithGoogle() async {
        busy = true
        errorMessage = nil
        do {
            let supabase = try await backend.supabaseURL()
            var components = URLComponents(url: supabase.appending(path: "/auth/v1/authorize"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "provider", value: "google"),
                URLQueryItem(name: "redirect_to", value: "agentline://auth-callback"),
            ]
            let callback = try await webSession.authenticate(
                using: components.url!,
                callbackURLScheme: "agentline",
                preferredBrowserSession: .shared
            )
            guard let session = Self.session(fromCallback: callback) else {
                throw AuthError.server("Google sign-in returned no session")
            }
            AuthStore.shared.signedIn(session)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    // MARK: - Helpers

    // Supabase's implicit flow returns tokens in the URL fragment; user id
    // and email live inside the JWT payload.
    static func session(fromCallback url: URL) -> AuthSession? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else { return nil }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            params[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }
        guard let access = params["access_token"], let refresh = params["refresh_token"] else { return nil }

        let expiresAt: Date = params["expires_at"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(params["expires_in"].flatMap(Double.init) ?? 3600)
        let claims = decodeJWTClaims(access)
        return AuthSession(
            accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
            userId: claims["sub"] as? String ?? "",
            email: claims["email"] as? String
        )
    }

    static func decodeJWTClaims(_ jwt: String) -> [String: Any] {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return [:] }
        var base64 = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        for _ in 0..<length {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            result.append(charset[Int(byte) % charset.count])
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
