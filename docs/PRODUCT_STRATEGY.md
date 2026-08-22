# Product strategy

## Wedge

Start with iPhone-first knowledge workers and commuters who already use AI and
want hands-free, recurring conversations with persistent specialist agents.

The job to be done:

> While driving or walking, help me use otherwise dead time for a purposeful
> conversation, remember where we left off, and turn it into something useful
> afterward.

The differentiator is the complete loop, not voice by itself:

1. reusable agent contact;
2. one-tap native call;
3. persistent, editable memory;
4. useful summary and actions;
5. export or automation;
6. an obvious reason to continue the next call.

## Product priorities

### P0: trustworthy first call

- Guided 90-second activation: choose a goal, select a template, audio check,
  short first call, immediate summary/memory result.
- Reliable call start, reconnect, background audio, and durable save.
- Automatically open the post-call result after hangup.
- Add password reset, verification/risk controls, support, privacy, consent,
  export, deletion, retention, and clear provider disclosure.
- Remove promises that are not true yet: the News agent has no grounded web
  tool, and unavailable local models must not appear as a working free tier.
- Define safety boundaries, especially for driving, children, crisis content,
  and medical/legal/financial topics.

### P1: prove repeat use

- Pre-call objective and quick agenda chips.
- “Continue where we left off” using the previous topic and memory.
- Memory provenance, correction, and deletion.
- Recurring routines and reminders.
- Native action destinations before developer-oriented MCP/webhook setup.
- Post-call quality feedback for latency, voice, accuracy, and usefulness.

### Later

Expand providers, local models, shared templates, and team/coach packs only
after the repeat-use loop demonstrates retention.

## Metrics

North star: weekly users completing at least two meaningful calls with an
intentional agent. A meaningful call can initially mean at least three minutes
or six user turns.

### Activation

- signup to agent/template created;
- first call start and connection success;
- first meaningful call within 10 minutes;
- summary viewed;
- second call within 7 days.

Initial beta targets:

- at least 60% signup to call start;
- at least 80% of starts connect during early beta, tightened to >98% before
  broad launch;
- at least 50% of starts become meaningful calls;
- at least 30% return for a second meaningful call within 7 days.

### Retention and quality

- D7 and W4 retained callers;
- repeat-agent share and calls per user per week;
- token-to-audio and interruption latency P50/P95;
- reconnect success;
- call-save success (>99.9%);
- transcript completeness and summary helpfulness;
- crash-free sessions (>99.5%).

### Business and guardrails

- free-to-paid conversion, paid churn, top-up rate, ARPPU;
- gross margin per minute after providers, summary, storage, and Apple fees;
- safety reports, deletion failures, unexpected spend, and current-information
  complaints.

## Monetization

The current four plans, credit packs, and three brain tiers are too complex
before product-market evidence. Test a free allowance plus one paid plan and
top-ups. Sell outcomes/quality rather than provider names. Do not promise
unlimited usage until concurrency, abuse controls, and unit economics are
proven. Target gross margin above 60% before scaling paid acquisition.

## Phased roadmap

1. **Foundation (2–4 weeks):** device matrix, durable saves, post-call result,
   monitoring, privacy/account controls, rate limits, safety, honest copy.
2. **Activation beta (4–6 weeks):** guided onboarding, five excellent
   templates, pre-call objective, full funnel analytics, 50–100 invite-only
   users and weekly interviews.
3. **Retention (6–10 weeks):** continue-call CTA, memory corrections, routines,
   native actions, quality feedback, lifecycle reminders.
4. **Scale:** pricing optimization, referrals/shared templates, grounded tools,
   provider expansion, and local/pipeline models.

Do not broadly launch until 30–50 external users demonstrate reliable calls and
at least 30% complete a second meaningful call within seven days.


## Committed experience features

- Continue the last conversation on every agent.
- Optional pre-call objective.
- Recurring call routines.
- Explicit Apple Reminders and Calendar action export.
- Post-call latency, voice, accuracy, and usefulness feedback.
- Correctable transcript sections with server-side re-summarization.
- Per-agent vocabulary and pronunciation guidance.
- Web-grounded live answers with audible source and publication-date attribution.
- Usage and spend warning before high-cost calls.
- Verified email signup, password reset, and session revocation.
- Persistent transcript, summary, objective, action items, and quality feedback.
- Privacy-controlled email/message and Markdown file sharing.
