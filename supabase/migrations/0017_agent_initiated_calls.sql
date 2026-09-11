-- Agent-initiated calls (ADR-8): external automations authenticate with a
-- revocable token, and APNs VoIP device tokens remain scoped to one user.

create table if not exists public.ring_api_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique check (length(token_hash) = 64),
  token_prefix text not null check (length(token_prefix) between 8 and 24),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

create index if not exists ring_api_tokens_user_id_idx
  on public.ring_api_tokens(user_id, created_at desc);
create index if not exists ring_api_tokens_active_hash_idx
  on public.ring_api_tokens(token_hash) where revoked_at is null;
create unique index if not exists ring_api_tokens_one_active_per_user_idx
  on public.ring_api_tokens(user_id) where revoked_at is null;

-- Rotation is one transaction: callers never lose the old token because an
-- insert failed after revocation.
create or replace function public.rotate_ring_api_token(
  p_user_id uuid,
  p_token_hash text,
  p_token_prefix text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_id uuid;
begin
  if p_user_id is null or length(p_token_hash) <> 64
     or length(p_token_prefix) not between 8 and 24 then
    raise exception 'invalid ring token parameters';
  end if;

  update public.ring_api_tokens
    set revoked_at = now()
    where user_id = p_user_id and revoked_at is null;

  insert into public.ring_api_tokens (user_id, token_hash, token_prefix)
    values (p_user_id, p_token_hash, p_token_prefix)
    returning id into new_id;

  return new_id;
end;
$$;

create table if not exists public.voip_devices (
  token text primary key check (token ~ '^[0-9a-f]{64,256}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists voip_devices_user_id_idx
  on public.voip_devices(user_id);

-- Atomic per-user throttle so a leaked ring token cannot continuously wake a
-- phone. The public endpoint currently permits six attempts per minute.
create table if not exists public.agent_ring_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  updated_at timestamptz not null default now()
);

create or replace function public.consume_agent_ring_rate_limit(
  p_user_id uuid,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  allowed boolean;
begin
  if p_user_id is null or p_limit < 1 or p_window_seconds < 1 then
    raise exception 'invalid ring rate-limit parameters';
  end if;

  insert into public.agent_ring_rate_limits as limits (
    user_id, window_started_at, attempts, updated_at
  ) values (
    p_user_id, now(), 1, now()
  )
  on conflict (user_id) do update set
    attempts = case
      when limits.window_started_at <= now() - make_interval(secs => p_window_seconds)
        then 1
      else limits.attempts + 1
    end,
    window_started_at = case
      when limits.window_started_at <= now() - make_interval(secs => p_window_seconds)
        then now()
      else limits.window_started_at
    end,
    updated_at = now()
  returning attempts <= p_limit into allowed;

  return allowed;
end;
$$;

alter table public.ring_api_tokens enable row level security;
alter table public.voip_devices enable row level security;
alter table public.agent_ring_rate_limits enable row level security;

revoke all on table public.ring_api_tokens from public, anon, authenticated;
revoke all on table public.voip_devices from public, anon, authenticated;
revoke all on table public.agent_ring_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.ring_api_tokens to service_role;
grant select, insert, update, delete on table public.voip_devices to service_role;
grant select, insert, update, delete on table public.agent_ring_rate_limits to service_role;

revoke all on function public.consume_agent_ring_rate_limit(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_agent_ring_rate_limit(uuid, integer, integer)
  to service_role;
revoke all on function public.rotate_ring_api_token(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.rotate_ring_api_token(uuid, text, text)
  to service_role;
