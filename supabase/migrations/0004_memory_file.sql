-- Per-agent distilled memory file (DESIGN-SPEC §3.10): updated by the
-- summary worker after every call, editable from the app.
alter table agents add column memory_file text not null default '';
