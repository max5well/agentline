-- agentline initial schema

create table agents (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  emoji text not null default '🤖',
  persona text not null,                -- system prompt: role, background, scenario
  voice text not null default 'marin', -- provider voice id
  tier text not null default 'fast' check (tier in ('local', 'fast', 'big')),
  tools jsonb not null default '[]',   -- tool configs, unused until tool support lands
  memory_enabled boolean not null default true, -- inject recent summaries into persona
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table calls (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references agents (id),
  provider text not null,              -- 'openai-realtime', 'gemini-live', 'personaplex', 'pipeline'
  started_at timestamptz not null,
  ended_at timestamptz,
  transcript jsonb not null default '[]', -- [{role, text, t}]
  summary text,                        -- written post-call by summary worker
  intents jsonb,                       -- extracted action items / intentions
  cost_cents integer,
  created_at timestamptz not null default now()
);

create index calls_agent_id_started_at_idx on calls (agent_id, started_at desc);
