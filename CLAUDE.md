# agentline — project context

Personal project of Max (max5well). iPhone app for real-time voice calls with configurable AI agents. See README.md for architecture.

## Stack

- iOS: SwiftUI, CallKit, AVAudioSession, WebRTC (native Swift, no React Native)
- Backend: Next.js (App Router, route handlers only — no UI), deployed on Vercel
- DB: Supabase Postgres
- Voice providers: OpenAI Realtime (launch), Gemini Live + PersonaPlex-on-Mac-Studio (later)
- Big-brain pipeline tier uses OpenRouter for the LLM slot (OpenRouter has NO realtime S2S — text only)

## Hard rules

- **Session scope**: work only inside this repo and `~/personal/repos/agentline-design` (design reference). Never read or touch Nox repos, other personal repos, Drive folders, or anything unrelated to agentline. Sessions run in dontAsk mode (no permission prompts) — this scope rule is the fence.
- API keys live only in backend env vars. The app receives ephemeral tokens, never raw keys.
- The voice session is abstracted behind one provider interface (`docs/ARCHITECTURE.md`); never code the app against a single provider's SDK directly.
- Keep the backend minimal: token minting, contacts CRUD, call records. No speculative features.

## Conventions

- Conventional commits, no ticket IDs
- English for code and docs
- Backend endpoints authenticated with `x-app-secret` header (personal app, single user)
