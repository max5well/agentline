import SwiftUI

// Language picker (DESIGN-SPEC §3.6): checkmark list with Suggested and
// All sections, searchable. Multi-select; first selection is the default.
struct LanguagePickerView: View {
    @Binding var selection: String?
    @State private var query = ""

    static let allLanguages = [
        "English", "German", "Spanish", "French", "Italian",
        "Portuguese", "Dutch", "Turkish", "Polish", "Japanese",
    ]

    var body: some View {
        List {
            if query.isEmpty, !suggested.isEmpty {
                Section("Suggested") {
                    ForEach(suggested, id: \.self, content: row)
                }
            }
            Section {
                ForEach(filtered, id: \.self, content: row)
            } header: {
                Text("All languages")
            } footer: {
                Text("The agent always speaks and understands this language during calls. You can ask it to switch mid-call.")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search languages")
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ language: String) -> some View {
        Button {
            toggle(language)
        } label: {
            HStack {
                Text(language)
                    .foregroundStyle(.primary)
                Spacer()
                if selected.contains(language) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var selected: [String] {
        (selection ?? "English")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func toggle(_ language: String) {
        var current = selected
        if let idx = current.firstIndex(of: language) {
            if current.count > 1 { current.remove(at: idx) } // keep at least one
        } else {
            current.append(language)
        }
        selection = current.joined(separator: ", ")
    }

    // Recently used (currently selected) + device languages.
    private var suggested: [String] {
        var result = selected
        for code in Locale.preferredLanguages.prefix(3) {
            if let name = Locale.current.localizedString(forLanguageCode: code),
               Self.allLanguages.contains(name), !result.contains(name) {
                result.append(name)
            }
        }
        return result
    }

    private var filtered: [String] {
        guard !query.isEmpty else { return Self.allLanguages }
        return Self.allLanguages.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
