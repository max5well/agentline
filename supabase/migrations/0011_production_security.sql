-- Production hardening: policies created in 0004 do not take effect until
-- RLS is enabled. The backend uses the service role, while these settings
-- prevent accidental direct-client access from bypassing tenant boundaries.

alter table agents enable row level security;
alter table calls enable row level security;
alter table profiles enable row level security;
alter table mcp_connections enable row level security;
alter table events enable row level security;
alter table apple_transactions enable row level security;

alter table profiles
  add constraint profiles_credit_nonnegative check (credit_cents >= 0);

alter table calls
  add constraint calls_time_order check (ended_at is null or ended_at >= started_at),
  add constraint calls_cost_nonnegative check (cost_cents is null or cost_cents >= 0);

create policy "users read their profile" on profiles
  for select to authenticated
  using (auth.uid() = user_id);

create policy "users read their events" on events
  for select to authenticated
  using (auth.uid() = user_id);

create policy "users read their purchases" on apple_transactions
  for select to authenticated
  using (auth.uid() = user_id);

create policy "users read their mcp connection" on mcp_connections
  for select to authenticated
  using (auth.uid() = user_id);
