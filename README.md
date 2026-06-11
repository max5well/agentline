# agentline

Personal iPhone app for real-time voice conversations with AI agents while commuting or walking. Feels like a WhatsApp/Skype call, but the contact book is full of AI agents you configured.

## Why

Maximize commute and walking time with natural, low-latency spoken conversations about topics worth learning. Transcripts and summaries feed back into other agents (Hermes, OpenClaw, Claude) so context carries over.

## Architecture

```
iPhone app (SwiftUI + CallKit + WebRTC)
        │
        ├── WebRTC ──────────► OpenAI Realtime (gpt-realtime)      [tier: fast/big]
        ├── WebRTC/WS ───────► Gemini Live                          [tier: fast, later]
        ├── audio stream ────► PersonaPlex 7B on Mac Studio (MLX)   [tier: local/free, later]
        │
        └── HTTPS ───────────► backend (Next.js on Vercel)
                                  ├── mints ephemeral provider tokens
                                  ├── agent contacts CRUD
                                  └── call records (transcript, summary)
                                          │
                                          ▼
                                      Supabase (Postgres)
```

Three "brain" tiers, selectable per agent contact:

| Tier  | Backend                                        | Trade-off                                       |
| ----- | ---------------------------------------------- | ----------------------------------------------- |
| local | PersonaPlex 7B on Mac Studio via Tailscale     | most natural turn-taking, shallow knowledge, $0 |
| fast  | gpt-realtime-mini / Gemini Flash Live          | casual topics, ~$4–6/hr                         |
| big   | pipeline STT → frontier LLM (OpenRouter) → TTS | deepest reasoning, +~200ms latency              |

MVP ships with the `fast`/`big` OpenAI Realtime path only; the provider interface is designed for all three from day one.

## Repo layout

- `backend/` — Next.js API (Vercel): token minting, contacts, call records
- `supabase/` — database migrations
- `ios/` — SwiftUI app (requires Xcode)
- `docs/` — architecture decisions

## Status

- [x] Backend scaffold: ephemeral token endpoint, Supabase schema
- [ ] iOS app: call screen + WebRTC + CallKit (blocked on Xcode install)
- [ ] Post-call summary worker
- [ ] Handoff fan-out (Hermes / OpenClaw / Claude via MCP)
- [ ] PersonaPlex local tier
