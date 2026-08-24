# Production readiness

Reviewed 2026-08-22. Agentline is a strong functional prototype, but it is not
ready for a broad App Store launch yet.

## Fixed in this change

- Removed the legacy application-wide secret that bypassed user scoping.
- Removed the authenticated endpoint that granted test billing credit.
- Made unverified StoreKit transactions impossible in production mode.
- Enabled RLS on all tenant and billing tables and added basic billing/time
  invariants.
- Added pull-request CI for a clean install, strict TypeScript check, and
  production backend build.

## P0 release blockers

- [ ] Test realtime calls end to end on physical devices, including AirPods,
      Bluetooth, CarPlay, lock/background, interruptions, auth expiry, poor
      network, and reconnects.
- [ ] Persist completed calls locally before upload; retry with an idempotency
      key so a network error cannot lose transcripts, summaries, or memory.
- [ ] Move summary/memory/handoff work out of the synchronous call-record
      request into a durable job with retries and observability.
- [ ] Replace the custom StoreKit JWS verifier with Apple's App Store Server
      Library and pinned Apple root certificates.
- [ ] Add distributed rate limits for signup, login, token minting, avatar
      generation, summaries, and voice previews.
- [ ] Make usage authoritative on the server. Client-supplied timestamps,
      model, cost, and completed-call uploads cannot be the billing ledger.
- [ ] Prevent SSRF for MCP and webhook URLs with a controlled outbound proxy or
      strict destination allowlist; encrypt stored connection secrets.
- [ ] Add structured request validation and size limits to every public route.
- [ ] Add privacy policy, terms, provider disclosure, recording/transcription
      consent, data export, call/account deletion, and retention controls.
- [ ] Add crash/error monitoring, latency metrics, redaction rules, alerts,
      backups, restore drills, and a rollback runbook.
- [ ] Remove the duplicate `backend/backend` route tree after confirming which
      webhook routes are deployed.
- [ ] Pin runtime/dependency versions and enable automated dependency and secret
      scanning.

## Release gates

| Area | Minimum gate |
| --- | --- |
| Call connection | >98% successful starts in beta |
| Crash-free sessions | >99.5% |
| Call record durability | >99.9% saved or safely queued |
| Reconnect | Tested on device; observable and recoverable |
| Tenant isolation | Automated authorization tests for every data route |
| Billing | Server-authoritative, replay-safe, verified Apple transactions |
| Security | No critical/high findings; SSRF and rate limits tested |
| Operations | Alerts, backups, rollback, support and incident owner documented |
| Product | 30–50 external users; at least 30% complete a second meaningful call within 7 days |

## Recommended verification pipeline

1. Backend: typecheck, build, unit tests, route integration tests against a
   disposable Supabase project, migration smoke test.
2. iOS: build and unit tests on the current Xcode version; UI smoke tests on at
   least one supported simulator.
3. Device beta: TestFlight matrix across supported iPhone/iOS versions and
   audio routes.
4. Security: dependency/secret scanning, authorization matrix, webhook/MCP
   egress tests, StoreKit replay and forgery tests.
5. Deployment: staged backend, database migration, smoke call, metrics check,
   then progressive rollout with a tested rollback.
