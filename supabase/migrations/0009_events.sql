-- Product events (decided 2026-06-13): generic funnel/analytics signals.
-- First consumer: quota_exceeded — counts how often free users hit the
-- hard stop, the trigger for revisiting pay-as-you-go on Free.
create table events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  type text not null,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index events_type_idx on events(type, created_at);
create index events_user_idx on events(user_id, created_at);
