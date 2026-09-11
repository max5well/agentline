-- Distributed signup throttling for serverless instances. Keys are HMACs of
-- IP/email values, so raw identifiers never enter the database.
create table if not exists public.signup_rate_limits (
  key_hash text primary key check (length(key_hash) = 64),
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  updated_at timestamptz not null default now()
);

alter table public.signup_rate_limits enable row level security;
revoke all on table public.signup_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.signup_rate_limits to service_role;

create or replace function public.consume_signup_rate_limit(
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed boolean;
begin
  if length(p_key_hash) <> 64 or p_limit < 1 or p_window_seconds < 1 then
    raise exception 'invalid rate-limit parameters';
  end if;

  insert into public.signup_rate_limits as limits (
    key_hash, window_started_at, attempts, updated_at
  ) values (
    p_key_hash, now(), 1, now()
  )
  on conflict (key_hash) do update set
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

revoke all on function public.consume_signup_rate_limit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_signup_rate_limit(text, integer, integer)
  to service_role;
