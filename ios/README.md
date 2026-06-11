# agentline iOS app

SwiftUI + CallKit + WebRTC. Design reference: [agentline-design/screens](https://github.com/max5well/agentline-design).

## Status

Builds and runs in the simulator on MockVoiceSession.

- `Theme.swift` — design tokens from the final screens (brass #C59B5C on #050607), glass card modifier
- `Models.swift` — Agent, CallRecord, TranscriptEntry, Tier (matches Supabase schema)
- `VoiceSession.swift` — the provider protocol (ADR-2)
- `MockVoiceSession.swift` — fake session cycling through all call states for simulator dev
- `BackendClient.swift` — token minting, agents, call records against the backend
- `ContactsView.swift`, `CallView.swift` — contacts home (recents + agents) and in-call screen with the animated orb
- `AgentEditorView.swift` — create/edit agent: emoji avatar, persona, voice, brain tier, memory
- `HistoryView.swift` — date-grouped call history with search
- `CallSummaryView.swift` — summary, action items, handoff buttons, expandable transcript
- `SettingsView.swift` — connected handoff tools + default handoff toggles
- `SampleData.swift` — fixture agents and call records (stable UUIDs)

All screens build and were verified in the simulator against MockVoiceSession. Screen hooks for headless screenshots: launch with `-autocall`, `-screen-editor`, `-screen-history`, `-screen-summary`, or `-screen-settings`.

Not started: OpenAIRealtimeSession (WebRTC), CallKit integration, Live Activity.

## First build (once Xcode is installed)

```bash
brew install xcodegen
cd ios && xcodegen generate
open Agentline.xcodeproj
```

Then set the signing team in Xcode (personal Apple Developer account) and run on simulator. The app runs fully on MockVoiceSession with sample agents — no backend needed for UI work.
