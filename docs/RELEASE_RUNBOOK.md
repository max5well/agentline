# Release runbook

This runbook is the source of truth for moving Agentline from PR validation to
production. It deliberately separates code preparation from production changes
so concurrent app work cannot silently trigger a deployment or migration.

## Ownership and sequencing

- App and UX work may continue on its own branch.
- Release-gate changes stay on a stacked branch based on PR #1.
- Only one person or session may change Supabase migration history at a time.
- Migrations are validated on a disposable branch before production.
- Production migration, merge, and deployment are separate approval points.

## 1. Reconcile the database baseline

The production project currently has schema objects but no recorded migration
history. Do not mark migrations as applied based only on filenames.

1. Export the production schema and compare every public table, column, type,
   default, constraint, index, trigger, function, grant, and RLS policy with
   migrations preceding `0011`.
2. Save the comparison output as a release artifact.
3. If and only if the schema is structurally equivalent, use
   `supabase migration repair --status applied <version>` for each verified
   historical migration.
4. Re-run `supabase migration list` and schema diff. A repair changes tracking
   state only; it must not be treated as schema validation.
5. If any object differs, capture the live schema with `supabase db pull` and
   review a baseline migration instead of repairing history.

## 2. Validate migrations on staging

Create a disposable Supabase branch only after the baseline is trustworthy.

- Apply the complete migration chain, including `0011` and `0012`.
- Run Supabase security and performance advisors.
- Verify ownership isolation with two authenticated test users.
- Verify check constraints reject negative credit/cost, invalid call times, and
  objectives longer than 500 characters.
- Verify authenticated users can read only their own profile, events,
  purchases, MCP connection, agents, and calls.
- Verify service-role backend operations still work.
- Delete the disposable branch after retaining the logs.

## 3. Verify deployment configuration

Required production variables, checked by name and target only:

| Variable | Production | Preview | Secret value handling |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | required | staging key | never print |
| `GEMINI_API_KEY` | required for Gemini | staging key | never print |
| `GEMINI_LIVE_MODEL` | optional rollback | optional | model identifier only |
| `SUPABASE_URL` | required | staging project | URL may be compared |
| `SUPABASE_SERVICE_ROLE_KEY` | required | staging project | never print |
| `APPLE_IAP_ALLOW_UNVERIFIED` | must be absent | optional in isolated test | never production |
| `APP_SECRET` | must be absent | must be absent | legacy bypass |

The backend pins Node `22.x` in `package.json`. Vercel documents that this
overrides the project setting, keeping CI and deployed functions on the same
major version.

## 4. Automated gates

- Backend CI: clean install, TypeScript check, and production build.
- iOS CI: regenerate the Xcode project, resolve packages, and compile the app
  plus extensions with code signing disabled.
- Add route integration tests against the staging Supabase branch before
  production deployment.
- Add dependency and secret scanning before branch protection becomes required.

## 5. Voice model test matrix

Run every row against staging. A row passes only when all six checks are
recorded: token/session creation, audio connection, first audible response,
tool call, usage write, and expected fallback.

| Agent setup | Expected primary | Expected fallback |
| --- | --- | --- |
| Fast, Gemini configured | `gemini-3.1-flash-live-preview` | Gemini 2.5 rollback through configuration |
| Fast, Gemini unavailable | `gpt-realtime-2.1-mini` | controlled error if OpenAI is also unavailable |
| Big | `gpt-realtime-2.1` | controlled error; never silently downgrade paid reasoning |
| Grounded current-information agent | configured Gemini Live model | controlled error if grounding cannot be provided |
| Budget pipeline | configured STT → LLM → TTS chain | controlled error or realtime-mini fallback according to product policy |

Automation must retain model/provider, timestamps, connection latency, first
response latency, tool-call outcome, usage delta, fallback reason, and redacted
error category. Provider credentials and ephemeral client secrets must never
appear in workflow logs.

## 6. Production rollout

1. Require passing backend and iOS checks on the final commit.
2. Apply the verified production migration once.
3. Deploy the exact reviewed commit through Git integration.
4. Run authenticated API smoke tests and one physical-device call.
5. Confirm logs, usage, billing, and call persistence.
6. Roll back immediately on tenant-isolation, billing, auth, or transcript-loss
   failures.
