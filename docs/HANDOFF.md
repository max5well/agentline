# Handoff: finish in-call tools, then continue

Written 2026-09-11 for the next agent picking up agentline. Read
`CLAUDE.md`, `README.md` and `docs/ARCHITECTURE.md` (ADR-1 to ADR-7) before
touching anything. The competitive rationale behind the roadmap below is in
`docs/FONIO_BENCHMARK.md`.

**Scope fence (from CLAUDE.md):** work only inside this repo and
`~/personal/repos/agentline-design`. Never touch Nox repos, other personal
repos or Drive folders.

## Where things stand

Commit `7b3209b` added in-call MCP tools (ADR-7): the MCP tools a user
connects become function declarations on the live voice session, per agent,
and the backend executes them mid-call.

What is verified: the backend passes `npx tsc --noEmit`.

What is **not** verified, at all:

- the iOS code has never been compiled (it was written in a Linux sandbox
  with no Xcode)
- `npx next build` has never run on this change (the sandbox has no npm
  registry access)
- migration 0015 has not been applied to Supabase
- no call has ever been made with tools enabled, on either provider

So treat everything below Task 1 as blocked until Task 1 is done.

## Task 1: get in-call tools working end to end

This is the whole job right now. Do not start new features before a real
call has successfully used a real tool on both providers.

### 1.1 Database

Apply `supabase/migrations/0015_in_call_tools.sql`. It adds
`agents.tools_enabled`, `mcp_connections.tools_json` and
`mcp_connections.call_tools`. Every backend read of those columns is
defensive (a pre-0015 schema degrades to "no tools" rather than failing),
so if tools silently never appear, check the migration actually ran.

### 1.2 Backend

```
cd backend
npx tsc --noEmit        # expected clean
npx next build          # never run against this change
```

Then deploy to Vercel (`agentline-chi.vercel.app`). New and changed files:

- `lib/tools.ts` (new): name sanitizing, JSON Schema reduction, provider
  shaping, the instruction block appended to the persona
- `lib/mcp.ts`: added `callMCPToolForResult` (returns the tool's text) and
  `flattenContent`; the old void `callMCPTool` now wraps it
- `app/api/mcp/call/route.ts` (new): executes one tool call from a live
  session, logs a `tool_call` event
- `app/api/mcp/route.ts`: POST caches the tool list, PATCH also accepts
  `callTools`, GET returns both
- `app/api/realtime/token/route.ts`: injects tools into the OpenAI client
  secret and into the Gemini response
- `app/api/agents/route.ts`: persists `tools_enabled`

### 1.3 iOS

```
cd ios
xcodebuild -project Agentline.xcodeproj -scheme Agentline \
  -destination 'generic/platform=iOS Simulator' build
```

Expect compile errors; nothing here has seen a compiler. Files touched:
`Models.swift` (new `Agent.toolsEnabled` plus a `JSONValue` tree),
`VoiceSession.swift` (new `.toolCall` / `.toolResult` events),
`BackendClient.swift` (`mcpCallTool`, `mcpSelectCallTools`, two new
`RealtimeToken` fields), `OpenAIRealtimeSession.swift`,
`GeminiLiveSession.swift`, `ConnectedTools.swift`, `ToolConnectViews.swift`,
`AgentEditorView.swift`, `CallView.swift`.

Two spots worth a second look because they were fixed by reading, not by
compiling: `JSONValue.raw` uses explicit returns on purpose (a switch
expression cannot unify branches of different types under `Any`), and
`CallView.stateLabel` needed `return switch` once a statement was put in
front of the switch.

### 1.4 Wire it up in the app

1. Settings, Tools, MCP: reconnect the server. This is what fills
   `tools_json`; without a reconnect after the migration there are no
   cached tools and every agent silently gets none.
2. In the same sheet, tick the tools agents may use in calls, then Save.
3. Agent editor, Tools section: turn on "Use my tools". The toggle is
   disabled while the cached list is empty, which is the usual symptom of a
   missing reconnect.
4. Call on the `big` tier (OpenAI Realtime) and on `fast` (Gemini Live) and
   ask for something that needs a tool.

### 1.5 What will probably break, and where to look

**OpenAI, the model calls a tool but nothing happens.** The session handles
`response.function_call_arguments.done` and `response.output_item.done`
(deduped by `call_id` in `handledToolCalls`). If the GA event names differ,
log every `type` in `handleServerEvent` and adapt.

**OpenAI, the tool runs but the agent goes quiet afterwards.** The model
does not resume on its own; `runTool` sends `conversation.item.create` with
a `function_call_output` and then `response.create`. That second event is
the suspect.

**Gemini, the socket dies right after connect with no `setupComplete`.**
The setup message now carries
`tools: [{googleSearch:{}}, {functionDeclarations:[...]}]`, and Gemini
rejects the entire setup on one unsupported schema keyword. Log the close
reason, then tighten `ALLOWED_KEYS` / `cleanSchema` in `lib/tools.ts`.
Second possibility: the Constrained endpoint may not accept `googleSearch`
and function declarations in one array. If so, drop `googleSearch` whenever
declarations exist, in `toolsPayload` in `GeminiLiveSession.swift`.

**A tool name never resolves.** Names are sanitized to
`^[a-zA-Z0-9_-]{1,64}$` and mapped back by re-sanitizing the cached list
(`resolveToolName`), so an empty or stale `tools_json` breaks resolution.
Reconnect the server.

**Latency.** This is the number that matters (see the benchmark: fonio
advertises 0.9 s). Measure user-stop to first agent audio with tools off
and on. A long tool list costs prompt tokens and time to first token;
`loadCallTools` caps at 24 tools, lower it if setup drags.

Every call writes a `tool_call` event with `{tool, ok, ms}` into the
`events` table (migration 0009). Use it rather than guessing.

### 1.6 Definition of done

A call on each provider where the agent announces what it is about to do,
the tool actually runs, the result is spoken back, and a deliberately
failing tool makes the agent say so instead of killing the call. Then
update the status list in `README.md`.

## Task 2: housekeeping, before anyone but Max uses this

- Signup has no rate limiting and no email confirmation (ADR-6 says so
  openly). Anyone who finds the backend URL can create an account.
- `backend/lib/summarize.ts` and `buildInstructions` in
  `app/api/realtime/token/route.ts` hardcode "Max" as the caller. The app
  has been multi-user since ADR-6, so every other user's agent greets the
  wrong person and their memory file is written about the wrong name.
- The summary worker runs inline on call save (ADR-4 accepts this). Move it
  off the request path once call volume justifies a cron or queue.
- The App Store privacy label has to name the data recipients, which now
  includes whatever MCP server the user connects.

## Task 3: the next feature, agents call you

The strongest differentiator versus ChatGPT Voice and Gemini Live, and the
inbound mirror of what fonio sells. Sketch:

`POST /api/agents/{id}/ring` with a short brief and an API token scoped to
the user. The backend sends a VoIP push; the app reports an incoming call
through CallKit (ADR-1 already names this as a reason for going native) and
the agent opens with the brief instead of a greeting. Uses: a morning
briefing at 07:30, Claude Code or OpenClaw ringing when a long task needs a
decision, Hermes calling back after a research job, n8n on any trigger.

Needs an APNs VoIP certificate and device testing; it cannot be validated
in a simulator.

## Then

`docs/FONIO_BENCHMARK.md` holds the rest in priority order: first call in 60
seconds with the signup wall moved behind the first summary; artifacts where
the user already lives (Reminders, Calendar, Notes, email digest); a simpler
money model (one minute currency, Stripe on the web so Apple does not take
30 percent of every overage minute); published latency numbers; a data and
retention page; and eventually a real phone number over OpenAI Realtime SIP.

## Conventions and traps

- Conventional commits, no ticket IDs. English for code and docs.
- The voice session stays behind the `VoiceSession` protocol (ADR-2). Never
  code the app against a provider SDK directly.
- API keys and MCP credentials live in backend env vars and the database.
  The app gets ephemeral tokens and relays tool calls; it never holds the
  MCP server URL or token (ADR-3, ADR-7).
- Keep the backend minimal: token minting, agents CRUD, call records, tool
  execution. No speculative endpoints.
- If you work through a sandboxed Linux VM on the Mac: there is no Xcode, no
  Swift toolchain and no npm registry there, so iOS builds and `next build`
  have to run on macOS. Git in that VM also cannot delete files, so it
  leaves `.git/index.lock` behind after every command; move it aside rather
  than expecting `rm` to work. A folder of such leftovers may still sit in
  `.git/agentline-stale/` and can be deleted from macOS.
