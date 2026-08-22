import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AuthSession
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Use at least 8 characters.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Choose New Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(busy || password.count < 8 || password != confirmation)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() async {
        busy = true
        do {
            try await BackendClient(config: BackendConfig.current)
                .completePasswordReset(accessToken: session.accessToken, newPassword: password)
            AuthStore.shared.signedIn(session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            busy = false
        }
    }
}
