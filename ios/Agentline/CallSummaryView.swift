import SwiftUI

// Post-call summary per design screen 07. Pushed from HistoryView and
// presented after hangup once the summary worker exists.
struct CallSummaryView: View {
    let record: CallRecord
    let agent: Agent

    @State private var transcriptOpen = false
    @State private var checked: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                head
                summaryCard
                if let intents = record.intents, !intents.isEmpty {
                    actionItems(intents)
                }
                handoffCard
                transcriptToggle
                if transcriptOpen {
                    transcriptCard
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .navigationTitle("Call Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var head: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                Text(agent.emoji).font(.system(size: 40))
            }
            .frame(width: 82, height: 82)
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(agent.persona.components(separatedBy: ".").first ?? "")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 12) {
                    Label(record.durationLabel, systemImage: "clock")
                    if let cents = record.costCents {
                        Text(String(format: "€%.2f", Double(cents) / 100))
                            .foregroundStyle(Color(hex: 0xE4C17B))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("Summary")
            Text(record.summary ?? "Summary is being written…")
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0xB9B8B4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard()
    }

    private func actionItems(_ intents: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Action Items")
            ForEach(intents, id: \.self) { item in
                Button {
                    if checked.contains(item) { checked.remove(item) } else { checked.insert(item) }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 1.5)
                            if checked.contains(item) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(width: 24, height: 24)
                        Text(item)
                            .font(.system(size: 15.5))
                            .foregroundStyle(Color(hex: 0xB9B8B4))
                            .strikethrough(checked.contains(item))
                        Spacer()
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassCard()
    }

    private var handoffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Handoff")
            handoffButton("Send to Obsidian", icon: "square.grid.2x2")
            handoffButton("Share with Hermes", icon: "sparkle")
            ShareLink(item: shareText) {
                handoffLabel("Share transcript", icon: "arrow.up.right")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard()
    }

    private func handoffButton(_ title: String, icon: String) -> some View {
        // Handoff fan-out is post-MVP (ADR-4); buttons are present but inert.
        Button {} label: { handoffLabel(title, icon: icon) }
    }

    private func handoffLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(title)
            Spacer()
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Color(hex: 0xE2BE7B))
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var transcriptToggle: some View {
        Button { withAnimation { transcriptOpen.toggle() } } label: {
            HStack {
                Text("Full Transcript")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(transcriptOpen ? 180 : 0))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .glassCard()
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if record.transcript.isEmpty {
                Text("No transcript captured for this call.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(record.transcript.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.role == "user" ? "You" : agent.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.role == "user" ? Theme.muted : Theme.accent)
                    Text(entry.text)
                        .font(.subheadline)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.text.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard()
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.bottom, 4)
    }

    private var shareText: String {
        var lines = ["Call with \(agent.name) — \(record.startedAt.formatted(date: .abbreviated, time: .shortened))"]
        if let summary = record.summary { lines.append("\nSummary:\n\(summary)") }
        if !record.transcript.isEmpty {
            lines.append("\nTranscript:")
            lines.append(contentsOf: record.transcript.map { "\($0.role == "user" ? "You" : agent.name): \($0.text)" })
        }
        return lines.joined(separator: "\n")
    }
}
