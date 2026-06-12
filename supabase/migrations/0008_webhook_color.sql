-- Generic webhook target per user; persisted avatar color per agent.
alter table profiles add column webhook_url text;
alter table agents add column color text;
