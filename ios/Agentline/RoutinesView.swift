import SwiftUI
import UserNotifications

struct CallRoutine: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var agentId: UUID
    var hour: Int
    var minute: Int
    var weekdays: Set<Int> = Set(1...7)

    var time: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }
}

enum RoutineStore {
    private static let key = "callRoutines.v1"

    static func load() -> [CallRoutine] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CallRoutine].self, from: data)) ?? []
    }

    static func save(_ routines: [CallRoutine]) {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func schedule(_ routine: CallRoutine, agentName: String) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw CocoaError(.userCancelled)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers(for: routine))
        for weekday in routine.weekdays {
            let content = UNMutableNotificationContent()
            content.title = routine.title
            content.body = "Ready for your call with \(agentName)?"
            content.sound = .default
            content.userInfo = ["agentId": routine.agentId.uuidString]

            var date = DateComponents()
            date.weekday = weekday
            date.hour = routine.hour
            date.minute = routine.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(routine.id.uuidString)-\(weekday)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    static func remove(_ routine: CallRoutine) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers(for: routine))
    }

    private static func identifiers(for routine: CallRoutine) -> [String] {
        (1...7).map { "\(routine.id.uuidString)-\($0)" }
    }
}

struct RoutinesView: View {
    let agents: [Agent]
    @State private var routines = RoutineStore.load()
    @State private var editing: CallRoutine?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(routines) { routine in
                Button {
                    editing = routine
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.title).foregroundStyle(.primary)
                        Text("\(agentName(routine.agentId)) · \(routine.time.formatted(date: .omitted, time: .shortened)) · \(dayLabel(routine.weekdays))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { RoutineStore.remove(routines[index]) }
                routines.remove(atOffsets: offsets)
                RoutineStore.save(routines)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .overlay {
            if routines.isEmpty {
                ContentUnavailableView(
                    "No routines yet",
                    systemImage: "repeat.circle",
                    description: Text("Schedule habits like Spanish practice every morning commute.")
                )
            }
        }
        .navigationTitle("Call Routines")
        .toolbar {
            Button("Add", systemImage: "plus") {
                if let agent = agents.first {
                    editing = CallRoutine(title: "", agentId: agent.id, hour: 8, minute: 0)
                }
            }
            .disabled(agents.isEmpty)
        }
        .sheet(item: $editing) { routine in
            RoutineEditorView(routine: routine, agents: agents) { updated in
                do {
                    try await RoutineStore.schedule(updated, agentName: agentName(updated.agentId))
                    if let index = routines.firstIndex(where: { $0.id == updated.id }) {
                        routines[index] = updated
                    } else {
                        routines.append(updated)
                    }
                    RoutineStore.save(routines)
                    errorMessage = nil
                } catch {
                    errorMessage = "Notifications are required to schedule this routine."
                }
            }
        }
    }

    private func agentName(_ id: UUID) -> String {
        agents.first(where: { $0.id == id })?.name ?? "Agent"
    }

    private func dayLabel(_ days: Set<Int>) -> String {
        if days == Set(1...7) { return "Every day" }
        if days == Set(2...6) { return "Weekdays" }
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var routine: CallRoutine
    let agents: [Agent]
    let onSave: (CallRoutine) async throws -> Void
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Routine name", text: $routine.title, prompt: Text("Spanish practice"))
                Picker("Agent", selection: $routine.agentId) {
                    ForEach(agents) { Text($0.name).tag($0.id) }
                }
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { routine.time },
                        set: {
                            routine.hour = Calendar.current.component(.hour, from: $0)
                            routine.minute = Calendar.current.component(.minute, from: $0)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Section("Days") {
                    ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, day in
                        Toggle(day, isOn: Binding(
                            get: { routine.weekdays.contains(index + 1) },
                            set: { enabled in
                                if enabled { routine.weekdays.insert(index + 1) }
                                else { routine.weekdays.remove(index + 1) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            try? await onSave(routine)
                            dismiss()
                        }
                    }
                    .disabled(saving || routine.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.weekdays.isEmpty)
                }
            }
        }
    }
}
