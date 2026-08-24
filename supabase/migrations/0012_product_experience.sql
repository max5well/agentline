-- Product experience fields: user-controlled context and review metadata.
alter table agents
  add column vocabulary text[] not null default '{}',
  add column web_grounding_enabled boolean not null default false;

alter table calls
  add column objective text,
  add column feedback jsonb;

alter table calls
  add constraint calls_objective_length
  check (objective is null or char_length(objective) <= 500);
