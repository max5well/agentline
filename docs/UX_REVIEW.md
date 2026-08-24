# UI/UX production review

## Product loop

The target experience is **prepare → talk → review → act → return**.

1. **Prepare:** Every manual call opens a lightweight sheet with “Continue our last conversation,” an optional objective, the selected model, and estimated cost. Big-tier calls show a spend warning before connection.
2. **Talk:** The agent receives the objective, rolling memory, vocabulary guidance, and grounding policy. Current-information agents use Gemini Live with audible source and date attribution.
3. **Review:** The summary surfaces the objective, outcome, action items, cost, editable transcript, and four-dimensional quality feedback.
4. **Act:** Users explicitly export selected information to Reminders, Calendar, email/messages, Markdown, Obsidian, Drive, or MCP.
5. **Return:** Recurring call routines make valuable agents habitual, while “Continue our last conversation” makes every agent feel persistent.

## Changes made

- Replaced immediate paid-call initiation with a pre-call preparation sheet.
- Added a high-cost warning and visible per-minute estimate.
- Added objective and continuity entry points.
- Added transcript correction and post-call ratings.
- Added action-item export to Apple Reminders and Calendar.
- Added privacy-controlled text and Markdown file sharing.
- Removed automatic connected-tool egress language and automatic backend pushes.
- Added recurring routine scheduling.
- Added vocabulary/pronunciation and current-information grounding controls.
- Added email verification, password recovery, current-device sign-out, and global session revocation.
- Updated voice-model names and default selections.
- Removed the obsolete debug credit bypass.

## Remaining launch validation

- Run the iOS target on a physical device to validate microphone, EventKit permission prompts, notification scheduling, deep links, and StoreKit purchases.
- Complete accessibility QA: VoiceOver order, Dynamic Type at accessibility sizes, Reduce Motion, contrast, and 44-point hit targets.
- Run usability sessions for first-agent creation, first call, transcript correction, and action export.
- Add automated UI tests for pre-call confirmation, expensive-model warning, transcript privacy toggle, and account recovery.
- Add backend rate limiting and abuse monitoring for open authentication endpoints.
- Verify email templates and both `agentline://auth-callback` and `agentline://reset-password` in the production Supabase project.
- Device management currently supports the current device plus “sign out all.” A named multi-device session list requires a first-party session registry because Supabase Auth does not expose device metadata.
