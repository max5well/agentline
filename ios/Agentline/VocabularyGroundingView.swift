import SwiftUI

struct VocabularyGroundingView: View {
    @Binding var vocabulary: [String]?
    @Binding var webGroundingEnabled: Bool?

    @State private var draftTerms = ""

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Use web-grounded answers",
                    isOn: Binding(
                        get: { webGroundingEnabled ?? false },
                        set: { webGroundingEnabled = $0 }
                    )
                )
            } footer: {
                Text("For news and current information, the agent searches first and names the source and date aloud. Grounded calls currently use Gemini Live.")
            }

            Section {
                TextEditor(text: $draftTerms)
                    .frame(minHeight: 150)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Vocabulary & pronunciation")
            } footer: {
                Text("One term per line. Add names, acronyms and specialist terminology. You can include a pronunciation, for example “NOX — pronounced knocks”.")
            }
        }
        .navigationTitle("Knowledge & Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftTerms = (vocabulary ?? []).joined(separator: "\n")
        }
        .onDisappear {
            vocabulary = draftTerms
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}
