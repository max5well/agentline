import SwiftUI

// Model picker (DESIGN-SPEC §3.9): checkmark list grouped by tier with
// prices in the headers. Selecting a model sets the tier internally.
struct ModelPickerView: View {
    @Binding var model: String?
    @Binding var tier: Tier

    var body: some View {
        List {
            tierSection(.local, header: "Home · free")
            tierSection(.fast, header: "Fast · estimated €0.10/min")
            Section {
                ForEach(ModelCatalog.all.filter { $0.tier == .big }, content: row)
                HStack {
                    Text("Custom (OpenRouter)…")
                    Spacer()
                    Text("Soon")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            } header: {
                Text("Big brain · estimated €0.40/min")
            } footer: {
                Text("Faster models feel more natural; bigger models think harder. Estimated cost shows live during every call.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tierSection(_ sectionTier: Tier, header: String) -> some View {
        Section(header) {
            ForEach(ModelCatalog.all.filter { $0.tier == sectionTier }, content: row)
        }
    }

    private func row(_ option: ModelOption) -> some View {
        Button {
            guard option.available else { return }
            model = option.id
            tier = option.tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .foregroundStyle(option.available ? .primary : .secondary)
                    Text(option.blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !option.available {
                    Text("Soon")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isSelected(option) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .disabled(!option.available)
    }

    private func isSelected(_ option: ModelOption) -> Bool {
        if let model { return model == option.id }
        // No explicit override: the tier's default is selected.
        switch tier {
        case .local, .fast: return option.id == "gemini-3.1-flash-live-preview"
        case .big: return option.id == "gpt-realtime-2.1"
        }
    }
}
