-- Multi-user accounts (ADR-6): every agent and call belongs to an
-- auth.users row. Existing rows predate auth and keep user_id null;
-- claim them after your first login with:
--   update agents set user_id = '<your-uid>' where user_id is null;
--   update calls  set user_id = '<your-uid>' where user_id is null;
alter table agents add column user_id uuid references auth.users(id) on delete cascade;
alter table calls add column user_id uuid references auth.users(id) on delete cascade;

create index agents_user_id_idx on agents(user_id);
create index calls_user_id_idx on calls(user_id);

-- The backend uses the service key and filters by the verified JWT's
-- user id; these policies are defense in depth for anon-key clients.
create policy "users own their agents" on agents
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users own their calls" on calls
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
