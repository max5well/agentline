-- Reproducible multi-user tenant baseline.
-- The original auth rollout was applied directly to the live database and was
-- never represented in the repository migration chain. Keep this migration
-- idempotent so existing deployments are repaired without data loss.

alter table agents add column if not exists user_id uuid;
alter table calls add column if not exists user_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'agents_user_id_fkey'
  ) then
    alter table agents
      add constraint agents_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'calls_user_id_fkey'
  ) then
    alter table calls
      add constraint calls_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end
$$;

create index if not exists agents_user_id_idx on agents(user_id);
create index if not exists calls_user_id_idx on calls(user_id);

alter table agents enable row level security;
alter table calls enable row level security;

drop policy if exists "users own their agents" on agents;
create policy "users own their agents" on agents
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "users own their calls" on calls;
create policy "users own their calls" on calls
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
