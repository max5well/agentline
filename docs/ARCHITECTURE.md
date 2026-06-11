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

The agent's tier picks the provider, identically in the app's session factory and the backend's `MODEL_BY_TIER`: `big` → OpenAI Realtime, `fast` and (until PersonaPlex exists) `local` → Gemini Live. A per-agent `model` override is honored only within the tier's provider family, so the two sides can never disagree. Agent voices are stored as OpenAI ids and mapped to Gemini prebuilt voices server-side.

Rationale: no realtime S2S aggregator exists (OpenRouter is text/TTS/STT only), so multi-provider means owning the abstraction ourselves.

## ADR-3: Ephemeral token minting on the backend

OpenAI Realtime supports short-lived client secrets (`POST /v1/realtime/client_secrets`). The backend mints one per call with the agent's persona baked into the session config. The iOS app connects WebRTC directly to OpenAI with that secret — backend is out of the audio path entirely (no latency added, no audio infra to run).

Gemini Live works the same way with ephemeral tokens (`v1alpha auth_tokens:create`), with one difference: the session config can't be baked into the token by our flow, so the backend returns `instructions` and `voice` alongside the token and the app sends them in its websocket setup message. The config still only travels over the `x-app-secret`-authenticated endpoint; the raw `GEMINI_API_KEY` never leaves the backend. While `GEMINI_API_KEY` is unset, Gemini tiers fall back to the OpenAI mini flow.

## ADR-4: Transcripts captured live, summary post-call

The Realtime API emits input/output transcription events during the session. The app buffers them and POSTs the full transcript on hangup. A backend worker then writes a summary + extracted intents (cheap model, Claude Haiku) into the call record. Handoff fan-out (Hermes Telegram, OpenClaw, Claude via MCP) hangs off the summary write — out of MVP scope.

## ADR-5: Single-user auth

Personal app. Backend endpoints check a static `x-app-secret` header against an env var. No user accounts, no Supabase Auth, until there's a second user.
