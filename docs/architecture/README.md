# Architecture diagrams

- `architecture.html` — system architecture: the iOS app, the Next.js API on Vercel,
  Supabase Postgres, and the external services (OpenAI, Gemini Live, App Store, MCP, PostHog).
- `dataflow.html` — call data flow: spoken audio and agent context into the realtime session,
  transcript to `/api/calls`, inline summary and memory distillation, and the consumers of the stored call.

Generated with Archify v2.17 (`architecture` + `dataflow`, showcase quality profile).
The `.json` files are the diagram sources; the `.html` files are self-contained interactive
viewers with no external assets — open them directly in a browser.
