# Architecture decisions

## ADR-1: Native Swift over React Native

CallKit (real call UX, lock-screen controls, incoming calls from agents), AVAudioSession edge cases (Bluetooth/CarPlay handoff, interruption by real calls), and background voip audio are all first-class only in native iOS. The app has one screen that matters; cross-platform buys nothing here.

## ADR-2: Provider abstraction for voice sessions

The app and backend code against one interface, not a provider SDK:

```swift
protocol VoiceSession {
    func start(agent: AgentContact, config: SessionConfig) async throws
    func end() async
    var events: AsyncStream<VoiceSessionEvent> { get }  // transcripts, state, cost ticks
    var audioRoute: AudioRouteController { get }
}
```

Implementations, in build order:

1. `OpenAIRealtimeSession` — WebRTC to OpenAI, ephemeral token from backend. Launch provider. **Built.**
2. `GeminiLiveSession` — cheap fast tier. Websocket + AVAudioEngine (PCM16 16 kHz up, 24 kHz down). **Built.**
3. `PersonaPlexSession` — audio streaming to Mac Studio (MLX port) over Tailscale. Free local tier.
4. `PipelineSession` — LiveKit room with server agent: Deepgram STT → OpenRouter LLM → Cartesia TTS. Big-brain tier, only way to get Claude as the brain.

The default lineup is `big` → `gpt-realtime-2.1`, `fast` and (until PersonaPlex exists) `local` → `gemini-3.1-flash-live-preview`. Fast may explicitly use `gpt-realtime-2.1-mini` as the OpenAI budget fallback. The backend validates model overrides against the tier allowlist and the iOS session factory routes by the resolved provider family. Set `GEMINI_LIVE_MODEL=gemini-2.5-flash-native-audio-preview-12-2025` for an operational rollback. Agent voices are stored as provider-neutral selections and mapped server-side.

Rationale: no realtime S2S aggregator exists (OpenRouter is text/TTS/STT only), so multi-provider means owning the abstraction ourselves.

## ADR-3: Ephemeral token minting on the backend

OpenAI Realtime supports short-lived client secrets (`POST /v1/realtime/client_secrets`). The backend mints one per call with the agent's persona baked into the session config. The iOS app connects WebRTC directly to OpenAI with that secret — backend is out of the audio path entirely (no latency added, no audio infra to run).

Gemini Live works the same way with ephemeral tokens (`v1alpha auth_tokens:create`), with one difference: the session config can't be baked into the token by our flow, so the backend returns `instructions` and `voice` alongside the token and the app sends them in its websocket setup message. The config travels only over a Supabase bearer-authenticated endpoint; the raw `GEMINI_API_KEY` never leaves the backend. While `GEMINI_API_KEY` is unset, Gemini tiers fall back to `gpt-realtime-2.1-mini`.

## ADR-4: Transcripts captured live, summary post-call

The Realtime API emits input/output transcription events during the session. The app buffers them and POSTs the full transcript on hangup. A backend worker then writes a summary + extracted intents (cheap model, Claude Haiku) into the call record. Handoff fan-out (Hermes Telegram, OpenClaw, Claude via MCP) hangs off the summary write — out of MVP scope.

## ADR-5: Single-user auth — superseded by ADR-6

Personal app. Backend endpoints check a static `x-app-secret` header against an env var. No user accounts, no Supabase Auth, until there's a second user.

## ADR-6: Multi-user accounts via Supabase Auth (supersedes ADR-5)

The app is going multi-user, so Supabase Auth (GoTrue) becomes the identity provider with three sign-in methods:

- **Email + password** — signup creates the user pre-confirmed via the admin API (no email infra to run).
- **Sign in with Apple** — native `AuthenticationServices` flow; the app exchanges Apple's `id_token` (+ nonce) for a Supabase session.
- **Google** — web OAuth via `ASWebAuthenticationSession` against Supabase's `/auth/v1/authorize?provider=google`, redirecting back to the `agentline://` scheme with tokens in the fragment. No Google SDK dependency.

All email/Apple auth calls are proxied through backend `/api/auth/*` routes, so API keys stay server-side (consistent with ADR-3) and the app only talks to our endpoints. The app stores the access/refresh token pair in the Keychain and refreshes on 401.

Data routes replace `x-app-secret` with `Authorization: Bearer <jwt>`, verified via `auth.getUser`, and every `agents`/`calls` row is scoped by `user_id`. The backend keeps the service key and filters explicitly; RLS policies on `user_id` exist as defense in depth. Signup is open to anyone who finds the backend URL — acceptable for now, no rate limiting yet.

## ADR-7: In-call tools — the agent uses MCP while you talk

MCP was a post-call path only: on hangup the digest was pushed to one chosen
tool. That makes agentline a nice voice notebook, not a gateway. The value is
in the call doing something — the benchmark against fonio.ai (`docs/FONIO_BENCHMARK.md`)
put this first, and it is what separates agentline from ChatGPT Voice, which
is free and preinstalled.

So the user's connected MCP tools become function declarations on the live
session, per agent.

**Where the tools come from.** The tool list is cached on `mcp_connections.tools_json`
when the user connects the server, and `call_tools` holds the subset they
allowed in calls (null = all). Token minting reads the cached list, so
enabling tools costs no round trip on the path that decides whether a call
feels instant. A reconnect in the MCP sheet refreshes the cache.

**Where they are injected.** Same split as ADR-3. OpenAI gets `tools` and
`tool_choice: "auto"` baked into the client secret server-side, so the app
never sees the list and cannot widen it. Gemini's session is configured by
the client's setup message, so the backend returns the declarations next to
`instructions` and `voice`, and the app merges them with `googleSearch`.
Provider-specific shaping lives in `lib/tools.ts`: names are sanitized to
`^[a-zA-Z0-9_-]{1,64}$` (deterministically, so the original is recovered by
re-sanitizing the cached list — no mapping state), and JSON Schemas are
reduced to the keyword subset both providers accept, since a stray `$schema`
or `oneOf` makes Gemini reject the whole setup message.

**Who executes them.** The app relays the model's function call to
`POST /api/mcp/call`; the backend resolves the name against the allowed list,
runs it over MCP and returns the text result. The MCP server URL and token
never reach the device, exactly as API keys don't (ADR-3). Only the audio
bypasses the backend.

**Failures are spoken, not thrown.** A failed tool returns 200 with the error
as its result, so the model says "that didn't work" instead of the app
treating a broken calendar as a broken call. Tool latency and failure rate
land in the `events` table as `tool_call` — the numbers that decide whether
in-call tools feel instant or broken.

Off by default per agent (`agents.tools_enabled`): an agent that had no reach
into the user's accounts yesterday must not silently gain it.
