-- Billing: per-user plan + prepaid credit, and the model per call so
-- usage can be metered by tier class (fast vs big).
create table profiles (
  user_id uuid primary key references auth.users (id),
  plan text not null default 'free' check (plan in ('free', 'plus', 'pro', 'max')),
  credit_cents integer not null default 0,
  created_at timestamptz not null default now()
);
alter table profiles enable row level security;

alter table calls add column model text;
