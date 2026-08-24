-- Avoid per-row auth function re-evaluation in read policies.
-- Wrapping auth.uid() in a scalar subquery lets Postgres initialize it once per statement.

drop policy if exists "users read their profile" on public.profiles;
create policy "users read their profile"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "users read their events" on public.events;
create policy "users read their events"
  on public.events
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "users read their purchases" on public.apple_transactions;
create policy "users read their purchases"
  on public.apple_transactions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "users read their mcp connection" on public.mcp_connections;
create policy "users read their mcp connection"
  on public.mcp_connections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);
