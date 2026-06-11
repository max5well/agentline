# agentline — Design Brief

## What this app is

agentline is a personal iOS app for having real phone calls with AI agents. You open it, see a contact book of agents you've configured (a history tutor, a startup sparring partner, a language coach), tap one, and you're in a live voice conversation with sub-second latency. It feels exactly like calling a friend on WhatsApp or FaceTime Audio, except the friend is an AI with a persona you wrote.

Primary context of use: driving and walking. The user is commuting in a car (phone mounted or in pocket, audio over Bluetooth/CarPlay) or walking through the city with AirPods. The screen is glanced at, not studied. Most of the experience is audio.

One user, personal app. No onboarding funnel, no signup screens, no marketing surfaces.

## Design principles

1. **A call, not a chat.** The mental model is the iOS Phone app, not ChatGPT. No chat bubbles during the call, no keyboard, no scrolling feed. Voice is the interface; the screen shows state.
2. **Glanceable at arm's length.** Every piece of mid-call information must be readable in under one second from a car mount: who am I talking to, is it hearing me, what's it costing. If it needs reading, it's wrong.
3. **Thumb-only, eyes-optional.** All mid-call controls reachable one-handed in the bottom third. Tap targets at minimum 56pt during calls, bigger than standard iOS. Mute and end-call must be hittable without looking.
4. **Calm, dark, premium.** Dark-first interface (driving at night, OLED). The app should feel like a beautifully crafted utility, closer to a high-end audio product than a playful AI toy. No mascots, no sparkle emoji aesthetics, no purple-gradient AI clichés.
5. **Motion communicates audio state.** The core visual element is a living indicator that shows listening vs. speaking vs. thinking without any text. This animation is the soul of the app and deserves the most design attention.
6. **Native iOS 26.** Liquid Glass materials, SF Pro, SF Symbols, standard navigation patterns, full Dynamic Type and dark mode support. It should feel like Apple could have shipped it.

## Screens

### 1. Contacts (home)

The agent contact book. A clean list or card grid of agents: avatar (emoji or generated portrait on a colored field), name, one-line role ("Modern history tutor"), and a small tier badge showing the brain level. Tapping a contact starts the call immediately, this is the primary action and should feel instant. A secondary tap area (info icon or long-press) opens the agent editor. Prominent but not shouty "+" to create a new agent. Recent calls can surface here as a small section, like Phone app favorites plus recents.

### 2. In-call (the hero screen)

Full-screen, minimal, dark. Top half: agent avatar and name, call timer, and the audio-state visualization (an orb, waveform, or particle field that breathes while listening, pulses while the agent speaks, and shimmers while it thinks). Bottom third: a control row like a native call: mute, audio route (speaker/Bluetooth), live captions toggle, push-to-talk toggle, and a red end-call button. A discreet live cost ticker (e.g. "0,42 €") sits near the timer, small but always visible. Optional live captions render as two lines max above the controls, never a scrolling transcript.

Push-to-talk mode is for noisy cars: the whole lower screen becomes one giant hold-to-talk surface. Design both states.

### 3. Post-call summary

Appears right after hangup. Title, duration, cost. Then the summary in readable prose, followed by extracted action items as a short checklist. Below: handoff row with buttons to send the summary onward ("Send to Hermes", "Save for Claude"), and an expandable full transcript. One screen, scrollable, no tabs.

### 4. Agent editor

Create or edit an agent. Fields: avatar picker, name, role one-liner, persona (large multiline text area, this is the system prompt), voice picker with a play-to-preview button per voice, and the **brain selector**: a three-position control (Local / Fast / Big) with one honest line under each option, e.g. "Free, runs at home, casual chats" / "Quick and cheap, everyday topics" / "Deepest reasoning, ~0,20 €/min". A toggle for "Remembers past calls". Keep it to one screen.

### 5. Call history

Reverse-chronological list of calls across all agents: agent avatar, date, duration, first line of the summary. Tapping opens the post-call summary screen for that call. Searchable.

## Visual direction

- **Palette:** near-black backgrounds, one restrained accent color used for the audio visualization and primary actions. Suggest a warm neutral or deep teal; avoid the generic AI purple/blue gradient.
- **Typography:** SF Pro throughout. Large, confident numerals for timer and cost (rounded variant welcome). Generous whitespace.
- **The orb/visualization** carries the personality. Per-agent accent tinting is welcome so each contact feels distinct, like contact colors in Phone.
- **Lock screen / Dynamic Island:** the call continues there via CallKit; design how the live activity looks (agent name, timer, mute state).

## Deliverables wanted from this design pass

1. Contacts home (list state and empty state)
2. In-call screen: listening, agent-speaking, thinking, and push-to-talk states
3. Post-call summary
4. Agent editor with the brain selector
5. Call history
6. Dynamic Island / Live Activity compact view

iPhone 15 Pro frame and up, dark mode primary, light mode optional. Portrait only.
