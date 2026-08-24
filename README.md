# agentline

Personal iPhone app for real-time voice conversations with AI agents while commuting or walking. Feels like a WhatsApp/Skype call, but the contact book is full of AI agents you configured.

## Why

Maximize commute and walking time with natural, low-latency spoken conversations about topics worth learning. Transcripts and summaries feed back into other agents (Hermes, OpenClaw, Claude) so context carries over.

## Architecture

```
iPhone app (SwiftUI + CallKit + WebRTC)
        │
        ├── WebRTC ──────────► OpenAI Realtime 2.1 / 2.1 Mini
        ├── WebRTC/WS ───────► Gemini 3.1 Flash Live (2.5 rollback)
        └── HTTPS ───────────► backend (Next.js on Vercel)
                                  ├── ephemeral provider tokens
                                  ├── authenticated agent/call APIs
                                  └── summaries, memory and handoffs
                                          │
                                          ▼
                                      Supabase (Postgres)
```

The iOS app uses a provider abstraction so realtime engines can evolve without coupling the UI to one vendor.

## Repo layout

- `backend/` — Next.js API: authentication, provider tokens, agents, calls, billing and handoffs
- `supabase/` — database migrations
- `ios/` — native SwiftUI app (requires Xcode)
- `docs/` — architecture, design, production and product decisions

## Current status

The core app, backend, multi-user auth, OpenAI/Gemini sessions, call history,
summaries, memory, integrations, and StoreKit flows are implemented. Physical
device end-to-end reliability, server-authoritative billing, durable background
processing, security controls, legal/account controls, and operational
observability remain release blockers.

Before deploying or distributing the app, read:

- [Production readiness](docs/PRODUCTION_READINESS.md)
- [Product strategy](docs/PRODUCT_STRATEGY.md)
- [Architecture decisions](docs/ARCHITECTURE.md)
- [UI/UX review](docs/UX_REVIEW.md)
- [Services and integrations](docs/INTEGRATIONS.md)
