-- Voice style prompt (delivery, accent, character) and explicit model
-- override (null = derive from tier).
alter table agents add column voice_style text not null default '';
alter table agents add column model text;
