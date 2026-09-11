# Agent-initiated calls

The code path is implemented but intentionally disabled in current builds. A
simulator can compile the PushKit and CallKit code, but it cannot receive or
validate a VoIP push. Do not call the feature complete until a physical iPhone
rings while the app is foregrounded, backgrounded, and terminated.

## Activate it

1. Join the paid Apple Developer Program and enable Push Notifications for the
   explicit `dev.max5well.Agentline` App ID.
2. Create an APNs authentication key and add these server-only variables to
   Vercel: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, and
   `APNS_TOPIC=dev.max5well.Agentline.voip`.
3. Re-enable the `entitlements` block for the Agentline target in
   `ios/project.yml`. It should point at `Agentline/Agentline.entitlements`;
   Debug and Release already select the development and production APNs
   environments respectively.
4. Set `AgentlineVoIPPushEnabled: true` in `ios/project.yml`, regenerate the
   Xcode project, and install that build on the iPhone. Debug installs register
   against APNs sandbox; TestFlight/App Store builds register in production.
5. Apply `supabase/migrations/0017_agent_initiated_calls.sql`, deploy the
   backend, then open **Settings → Agents Call You** on the phone. The screen
   should report both the iPhone and push service as configured.

The `.p8` key accepts literal newlines or `\\n` escapes. Never put it in the
iOS project or a `NEXT_PUBLIC_*` variable.

## Call from an automation

Create a ring token in **Settings → Agents Call You** and copy it immediately;
the backend stores only its hash and cannot show it again. The same screen can
copy a ready-to-edit cURL command for any agent.

```bash
curl -X POST 'https://agentline-chi.vercel.app/api/agents/AGENT_UUID/ring' \
  -H 'Authorization: Bearer al_ring_REPLACE_ME' \
  -H 'Content-Type: application/json' \
  -d '{"brief":"The research is ready. Ask me which option to pursue.","deadline":"2026-09-12T08:00:00Z"}'
```

The brief is required and limited to 1,000 characters. `deadline` is optional.
The endpoint returns `202` after at least one registered device accepts the APNs
request, `409` when no phone is registered, `429` after six ring attempts in one
minute, and `502` if APNs rejects every device. Invalid or unregistered device
tokens are removed automatically.

## Physical-device definition of done

- A sandbox push rings a Debug build from foreground, background, and terminated
  states, and a production push rings a TestFlight build.
- The system incoming-call UI shows the correct agent and decline does not open
  the app call screen.
- Answer holds the system UI on connecting until the realtime provider is ready;
  OpenAI and Gemini each speak the brief first without a generic greeting.
- Hang-up, Focus/Do Not Disturb, network failure, expired auth, token rotation,
  stale device cleanup, and repeated/rate-limited requests fail cleanly.
- The resulting call is saved with its objective and the `agent_ring` event is
  present without storing the brief in analytics metadata.
