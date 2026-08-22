import SwiftUI
import UIKit

struct AccountSecurityView: View {
    @State private var auth = AuthStore.shared
    @State private var busy = false
    @State private var status: String?
    @State private var showRevokeConfirmation = false

    var body: some View {
        Form {
            Section("Email") {
                LabeledContent("Address", value: auth.session?.email ?? "Unknown")
                Label("Verified by the authentication provider", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Send password-reset email") {
                    Task { await resetPassword() }
                }
                .disabled(busy || auth.session?.email == nil)
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIDevice.current.name)
                        Text("This device · active now")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Current").font(.caption.weight(.semibold)).foregroundStyle(.green)
                }

                Button("Sign out this device", role: .destructive) {
                    auth.signOut()
                }
                Button("Sign out all devices", role: .destructive) {
                    showRevokeConfirmation = true
                }
                .disabled(busy)
            } header: {
                Text("Sessions & devices")
            } footer: {
                Text("Signing out all devices revokes every refresh token for this account, including this phone.")
            }

            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Account & Security")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out everywhere?",
            isPresented: $showRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out all devices", role: .destructive) {
                Task { await revokeAll() }
            }
        } message: {
            Text("You’ll need to sign in again on every device.")
        }
    }

    private func resetPassword() async {
        guard let email = auth.session?.email else { return }
        busy = true
        do {
            try await BackendClient(config: BackendConfig.current).requestPasswordReset(email: email)
            status = "Password-reset email sent."
        } catch {
            status = error.localizedDescription
        }
        busy = false
    }

    private func revokeAll() async {
        busy = true
        do {
            try await BackendClient(config: BackendConfig.current).signOutAllDevices()
            auth.signOut()
        } catch {
            status = error.localizedDescription
            busy = false
        }
    }
}
