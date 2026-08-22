import CoreTransferable
import EventKit
import EventKitUI
import SwiftUI
import UniformTypeIdentifiers

struct CallExportFile: Transferable {
    let filename: String
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .markdown) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(export.filename)
                .appendingPathExtension("md")
            try Data(export.markdown.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum AppleActionExporter {
    @MainActor
    static func addReminders(_ items: [String]) async throws {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw CocoaError(.userCancelled)
        }
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item
            reminder.calendar = store.defaultCalendarForNewReminders()
            try store.save(reminder, commit: false)
        }
        try store.commit()
    }
}

struct CalendarDraftSheet: UIViewControllerRepresentable {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        let store = EKEventStore()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = Date().addingTimeInterval(3600)
        event.endDate = event.startDate.addingTimeInterval(1800)
        controller.event = event
        controller.editViewDelegate = context.coordinator
        Task { _ = try? await store.requestFullAccessToEvents() }
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            dismiss()
        }
    }
}

struct TranscriptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [TranscriptEntry]
    let agentName: String
    let onSave: ([TranscriptEntry]) async throws -> Void

    @State private var saving = false
    @State private var errorMessage: String?

    init(
        transcript: [TranscriptEntry],
        agentName: String,
        onSave: @escaping ([TranscriptEntry]) async throws -> Void
    ) {
        _draft = State(initialValue: transcript)
        self.agentName = agentName
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(draft.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft[index].role == "user" ? "You" : agentName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "Transcript",
                            text: Binding(
                                get: { draft[index].text },
                                set: {
                                    draft[index] = TranscriptEntry(
                                        role: draft[index].role,
                                        text: $0,
                                        t: draft[index].t
                                    )
                                }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(2...8)
                    }
                }
                .onDelete { draft.remove(atOffsets: $0) }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Correct Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await onSave(draft)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                saving = false
                            }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

struct QualityFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: CallFeedback
    let onSubmit: (CallFeedback) async throws -> Void
    @State private var submitting = false
    @State private var errorMessage: String?

    init(initial: CallFeedback?, onSubmit: @escaping (CallFeedback) async throws -> Void) {
        _feedback = State(initialValue: initial ?? CallFeedback(
            latency: 3, voice: 3, accuracy: 3, usefulness: 3
        ))
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                rating("Latency", value: $feedback.latency)
                rating("Voice", value: $feedback.voice)
                rating("Accuracy", value: $feedback.accuracy)
                rating("Usefulness", value: $feedback.usefulness)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Rate This Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitting = true
                        Task {
                            do {
                                try await onSubmit(feedback)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                submitting = false
                            }
                        }
                    }
                    .disabled(submitting)
                }
            }
        }
    }

    private func rating(_ title: String, value: Binding<Int>) -> some View {
        Section(title) {
            HStack {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value.wrappedValue = score
                    } label: {
                        Image(systemName: score <= value.wrappedValue ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }
}
