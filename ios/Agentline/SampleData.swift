import Foundation

// Fixture data for simulator development against MockVoiceSession.
// Stable UUIDs so call records can reference agents across launches.

extension Agent {
    static let maya = Agent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Maya", emoji: "📜",
        persona: "Modern history tutor. Socratic, opinionated, concrete.",
        voice: "marin", tier: .big, memoryEnabled: true
    )
    static let marco = Agent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Marco", emoji: "🌱",
        persona: "Startup sparring partner. Challenges every assumption.",
        voice: "cedar", tier: .fast, memoryEnabled: true
    )
    static let elena = Agent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Elena", emoji: "🗣️",
        persona: "Spanish coach. Conversational immersion, gentle corrections.",
        voice: "marin", tier: .fast, memoryEnabled: true
    )

    static let samples: [Agent] = [maya, marco, elena]
}

extension CallRecord {
    static let samples: [CallRecord] = {
        let now = Date.now
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            CallRecord(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
                agentId: Agent.maya.id, provider: "openai-realtime",
                startedAt: ago(2), endedAt: ago(2).addingTimeInterval(28 * 60),
                transcript: [
                    .init(role: "user", text: "Walk me through the July Crisis. Why did deterrence fail?", t: 4),
                    .init(role: "agent", text: "Because every actor thought the other side was bluffing. Austria wanted a local war, Germany gave the blank cheque assuming Russia wasn't ready…", t: 9),
                    .init(role: "user", text: "So the alliance system made escalation automatic?", t: 41),
                    .init(role: "agent", text: "Not automatic — that's the schoolbook version. Mobilization timetables made it fast, but there were exit ramps. Grey's ambiguity mattered more than the treaties.", t: 47),
                ],
                summary: "Reviewed the causes of World War I, focusing on the alliance system, the July Crisis, and the assassination that triggered the conflict. Also covered home-front life, propaganda, and women's wartime roles. Maya suggested primary sources for the next essay.",
                intents: ["Read \"The Sleepwalkers\" chapter 3", "Outline essay on causes of WWI"],
                costCents: 360
            ),
            CallRecord(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000002")!,
                agentId: Agent.marco.id, provider: "openai-realtime",
                startedAt: ago(3.5), endedAt: ago(3.5).addingTimeInterval(41 * 60),
                transcript: [
                    .init(role: "user", text: "I want to pitch the agent contact book as the wedge.", t: 5),
                    .init(role: "agent", text: "Why would anyone pay for that when ChatGPT has voice mode for free? Convince me.", t: 11),
                ],
                summary: "Refined the pitch and the next investor ask. Marco pushed back on the wedge framing and the pricing model.",
                intents: ["Rewrite one-liner without the word 'platform'", "Get 5 user interviews before next call"],
                costCents: 180
            ),
            CallRecord(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000003")!,
                agentId: Agent.elena.id, provider: "openai-realtime",
                startedAt: ago(26), endedAt: ago(26).addingTimeInterval(26 * 60),
                transcript: [
                    .init(role: "user", text: "Quiero practicar el subjuntivo hoy.", t: 3),
                    .init(role: "agent", text: "¡Perfecto! Empecemos con deseos: espero que tú…", t: 7),
                ],
                summary: "Practiced present subjunctive and travel vocabulary. Elena corrected recurring errors with ser/estar in opinions.",
                intents: ["Review subjunctive trigger phrases"],
                costCents: 95
            ),
            CallRecord(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000004")!,
                agentId: Agent.maya.id, provider: "openai-realtime",
                startedAt: ago(75), endedAt: ago(75).addingTimeInterval(33 * 60),
                transcript: [],
                summary: "Covered the Congress of Vienna and why the concert system held for forty years.",
                intents: nil,
                costCents: 410
            ),
        ]
    }()
}
