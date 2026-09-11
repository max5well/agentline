# Service and integration inventory

## Production runtime

| Service | Purpose | Evidence / configuration | Needed for launch |
| --- | --- | --- | --- |
| Vercel | Hosts the Next.js backend at `agentline-chi.vercel.app` | iOS production URL and README architecture | Yes, or replace with another Next.js host |
| Supabase | Authentication, Postgres, RLS, call history, agents, profiles, billing state | `@supabase/supabase-js`, migrations, `SUPABASE_URL`, service-role key | Yes |
| OpenAI API | Realtime 2.1 and 2.1 Mini voice sessions; summarization path | `OPENAI_API_KEY` | Yes for OpenAI tiers and summaries |
| Google Gemini API | Gemini 3.1 Flash Live primary fast model; Gemini 2.5 rollback | `GEMINI_API_KEY`, optional `GEMINI_LIVE_MODEL` | Yes for the default fast tier |
| Apple StoreKit 2 / App Store Connect | Subscriptions and prepaid credit packs | native StoreKit code and StoreKit test configuration | Yes for paid App Store launch |
| Apple platform services | Microphone, CallKit, Live Activities, notifications, Reminders and Calendar | native iOS frameworks and Info.plist usage descriptions | Yes for the respective features |

## Product analytics and optional destinations

| Service | Status | Notes |
| --- | --- | --- |
| PostHog EU | SDK included, currently disabled because the project API key is blank | Recommended before beta, with privacy review and no transcript/persona properties |
| Google OAuth | Used through Supabase for sign-in | Configure provider and `agentline://auth-callback` in Supabase |
| Google Drive | Optional explicit export destination | Requires the app’s own OAuth/client configuration; a ChatGPT connector does not configure the shipped iOS app |
| Obsidian | Optional local URL-scheme export | No server account or secret required |
| MCP server | Optional user-configured explicit export | Treat remote URLs/tokens as sensitive; keep SSRF and secret-encryption launch gates |
| Webhook | Optional user-configured explicit export | Manual sending is preferred; validate allowlists and SSRF controls before broad release |
| Apple Reminders / Calendar | Optional explicit action export | Requests permission only when the user chooses the action |
| Email / Messages / Files | Uses the iOS share sheet | No transactional email vendor is required for call-file sharing |

## App Store privacy disclosure draft

Review this mapping against the final binary and App Store Connect form before
every release. It is a technical inventory, not a substitute for the public
privacy policy or legal review.

| Data | Purpose | Linked to the user | Tracking | Processor / recipient |
| --- | --- | --- | --- | --- |
| Email address, account ID and optional display name | Account management and authentication | Yes | No | Supabase |
| Live microphone audio and the model's audio response | Real-time voice conversation | Yes, for the active session | No | OpenAI or Google Gemini, according to the selected model |
| Transcript, summary, action items, agent persona and memory | App functionality, history and personalization | Yes | No | Supabase; OpenAI for summary/memory processing |
| Purchase and subscription state | Payments, entitlement and fraud prevention | Yes | No | Apple and Supabase |
| Product interactions and diagnostics | Analytics and reliability | Yes when analytics is enabled | No | PostHog EU and hosting logs on Vercel |
| User-selected tool arguments, results or call exports | Perform an action or explicit export requested by the user | Depends on the destination account | No | The specific MCP server, webhook, Google Drive, Obsidian, or Apple app selected by the user |

The in-app disclosure and public privacy policy must say that enabling an MCP
tool can send the content needed for that action to a server chosen by the
user. Agentline cannot control that server's retention or downstream use. Do
not claim that transcripts stay only on-device or that OpenAI is the sole AI
processor: the selected voice tier determines whether OpenAI or Google receives
the live audio and conversation context.

## Not present

- **Stripe is not used.** Billing is implemented with Apple StoreKit and App Store receipts.
- No Sentry SDK is present.
- No Resend, SendGrid, or other transactional-email SDK is present. Supabase Auth sends verification and password-recovery emails.
- No Cloudflare runtime dependency is present.

## ChatGPT connector recommendation

The GitHub connector is the only connector needed to review and modify this repository.

Connecting Google Drive or Gmail could help inspect test exports or delivered auth emails, but it would not configure the iOS app’s OAuth credentials. Vercel and Supabase production validation require access to those projects or their deployment logs/configuration; there is no need to connect unrelated plugins. Never paste service-role keys or provider API keys into chat.
