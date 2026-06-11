# agentline iOS app

SwiftUI + CallKit + WebRTC. Design reference: [agentline-design/screens](https://github.com/max5well/agentline-design).

## Status

Source skeleton written, **not yet compiled** (Xcode not installed on this machine yet). First build will likely need minor fixes.

- `Theme.swift` — design tokens from the final screens (brass #C59B5C on #050607), glass card modifier
- `Models.swift` — Agent, CallRecord, TranscriptEntry, Tier (matches Supabase schema)
- `VoiceSession.swift` — the provider protocol (ADR-2)
- `MockVoiceSession.swift` — fake session cycling through all call states for simulator dev
- `BackendClient.swift` — token minting, agents, call records against the backend
- `ContactsView.swift`, `CallView.swift` — contacts home and in-call screen with the animated orb

Not started: OpenAIRealtimeSession (WebRTC), CallKit integration, agent editor, history, post-call summary screen, Live Activity.

## First build (once Xcode is installed)

```bash
brew install xcodegen
cd ios && xcodegen generate
open Agentline.xcodeproj
```

Then set the signing team in Xcode (personal Apple Developer account) and run on simulator. The app runs fully on MockVoiceSession with sample agents — no backend needed for UI work.
