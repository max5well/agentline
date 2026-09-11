# Benchmark: what fonio.ai gets right, and what it means for agentline

Date: 2026-09-11. Sources: fonio.ai homepage and pricing, Sacra profile, Zeeg guide, telefon.services test, OMR/Capterra reviews.

## fonio.ai in one paragraph

Inbound AI phone assistant for European SMBs (doctors, tradespeople, hotels, realtors). Answers the business's phone 24/7, books appointments, qualifies leads, forwards calls, and emails transcript + summary after every call. About 10,000 customers, roughly $10M ARR (July 2026), $17M seed at $140M valuation, ~2M automated calls per month, ~200 calls per customer per month. Stack: hosted at Hetzner Nuremberg, OpenAI models via Azure EU, own telephony (fonio numbers or SIP trunk), ~0.9 s average response time. Pricing: plan + included minutes + per-minute overage (Solo 99 EUR / 1,000 min, Team 299 EUR / 3,600 min, Scale 499+ EUR). No free trial, 30-day money-back. 450+ reseller partners, 90% Germany.

## Why it works (the transferable parts)

1. Outcome, not technology. Fonio sells "no missed call, booked appointments", never "realtime voice AI". Every homepage section is a job to be done.
2. Time to first "aha" under 20 minutes, test call in 30 seconds, five ready-made use-case templates. No code, no prompt engineering visible to the user.
3. The call does things. Booking, CRM lookup, RAG knowledge, live web search, call forwarding happen during the call. The conversation is a means to an action.
4. Artifacts land where the customer already lives: email/SMS with transcript, summary, next steps. Integrations (Slack, HubSpot, Salesforce, Calendly, cal.com, webhooks) are the product surface after the call.
5. Latency and voice quality are measured and advertised (0.9 s, 120+ voices, 60+ languages). Reviews praise "callers do not notice it is AI".
6. Trust as a feature: GDPR, EU AI Act, Hetzner, Azure EU, zero data retention on Scale. Decisive for German buyers.
7. Simple unit of value: minutes. One plan, one number, one currency. (Reviewers still call the cost structure confusing, which shows how little tolerance there is.)
8. Same brain, more channels: WhatsApp bot, email, web chat reuse the assistant configuration. Expansion is channel-shaped, not feature-shaped.
9. Distribution through verticals and resellers rather than horizontal "AI" marketing.

## Where agentline stands (repo state, Sept 2026)

Built: native iOS app, CallKit, OpenAI Realtime + Gemini Live behind one VoiceSession protocol, three brain tiers, per-agent persona/voice/language/model, rolling memory file per agent, live captions, transcripts + summaries + action items, handoff to Obsidian / Google Drive / MCP tool / generic webhook, 7 agent templates + onboarding, Siri intents, Live Activity, Supabase Auth (email/Apple/Google), plans + quotas + credit + Apple IAP, PostHog.

Not yet: in-call tool use, agent-initiated calls, PSTN / phone number, PersonaPlex local tier, summary worker off the request path, rate limiting on signup, non-"Max" memory prompts (summarize.ts still hardcodes the user name).

## The mirror image

fonio: customers call the business's agent (inbound, B2B). agentline: the user calls their own agents (outbound, prosumer). Same tech: realtime voice, persona, tools, transcript, summary, integrations. The difference that matters for product strategy: fonio's moat is the phone number plus actions; agentline's moat has to be "the phone is how you reach your agents and your agents reach you", with consequences on both ends of the call. Without that, agentline competes with ChatGPT Voice and Gemini Live, which are free and preinstalled.

## Recommendations, in priority order

### 1. In-call tools via MCP (the gateway)

Today MCP is post-call only (send the digest). Fonio's core value is actions during the call. Wire realtime function calling: backend lists the tools of the user's connected MCP servers, injects them into the session config at token minting (OpenAI Realtime and Gemini Live both support tools), the app forwards tool calls to `POST /api/mcp/call` and returns results into the session. First-party tools worth shipping alongside: web search (Gemini grounding already exists), calendar read, Reminders/Notes write. This single change turns "chat with a persona" into "operate my agents by voice".

### 2. Agents call you (the inbound analog)

ADR-1 already lists incoming calls from agents as a CallKit reason. Ship it: `POST /api/agents/{id}/ring` with a brief (text) and optional deadline, authenticated per user with an API token. Backend sends a VoIP push, the app shows a real incoming call, the agent opens with the brief. Use cases: a morning briefing agent at 07:30, Claude Code or OpenClaw ringing when a long task needs a decision, Hermes calling back after a research job, n8n on any trigger. Nobody else offers this; it is the strongest differentiator versus ChatGPT Voice and it makes the "gateway" story literal.

### 3. First call in 60 seconds, signup after

Fonio's 30-second test call is the conversion engine. agentline: pick a template, call, get the summary, then create the account to keep it. Free plan already has 30 fast minutes; move the signup wall behind the first summary. Measure install -> first call -> first handoff as the funnel.

### 4. Artifacts where the user lives

Today: Obsidian, Drive, MCP, webhook. Add the zero-friction ones on iOS: action items -> Apple Reminders (EventKit), decisions/dates -> Calendar, summary -> Apple Notes, optional email digest after each call. Fonio sends email + SMS by default; make one default handoff part of onboarding so every call produces something outside the app.

### 5. Simplify the money

fast/big minute quotas plus credit plus IAP packs is the structure reviewers punish Fonio for, and agentline has more moving parts. Options: one minute currency (a big minute costs N fast minutes, shown once), or plans that differ only in minutes with "quality" as a per-agent setting. Also: Apple takes 30% of every per-minute overage. Since the DMA, EU apps may link to web checkout; Stripe for plans on the web, IAP only where required. billing.ts already anticipates Stripe.

### 6. Measure what Fonio advertises

Instrument per-turn latency (user stop -> agent first audio), drop/reconnect rate, and summary quality per provider and tier in PostHog. Publish the numbers in-app (tier picker: "~0.6 s" instead of "quick and cheap"). Build a small eval set of 20 scripted calls per provider to catch regressions when models change.

### 7. Trust as a feature

Prosumers in DACH care as much as SMBs. A data page in Settings (which provider hears the audio, retention, region), a per-agent "no transcript storage" toggle, EU routing where available (Azure OpenAI Realtime EU, Supabase EU region), and the local PersonaPlex tier positioned explicitly as the private tier.

### 8. A real phone number (later)

Fonio's whole business is the number. For agentline the version is: call your agents from any phone or car without the app, and agents can call your real number. OpenAI Realtime supports SIP ingress directly (also via Azure OpenAI, which gives an EU path); a Twilio Elastic SIP trunk pointed at it, with the backend accepting the incoming-call webhook and attaching the agent config, avoids running audio infrastructure. Check SIP pricing and Azure region availability before committing. Keep the backend out of the audio path, as today.

### 9. Distribution shaped like the users

Fonio uses verticals and resellers. agentline's equivalent: recipes and integrations for the agent-builder crowd. "Ring me from Claude Code when the PR is ready" (a hook + curl), OpenClaw and Hermes plugins, an n8n node, a public MCP server for agentline itself. Each recipe is a landing page and a community post.

## Housekeeping before any of this is public

Rate limiting and email confirmation on signup (ADR-6 notes both are missing). Memory and summary prompts must use the account's name, not "Max". Summary worker off the request path once call volume grows (Vercel cron or Supabase queue). App Store review needs a privacy nutrition label that matches the provider list above.

## North-star metrics to copy

Fonio: ~200 calls per customer per month, ~$1,000 revenue per customer per year. agentline equivalents: calls per active user per week, share of calls with a handoff or a tool call, agent-initiated calls answered, minutes per paying user, gross margin per minute after provider and Apple costs.
