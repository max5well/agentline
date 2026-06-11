-- Per-agent default spoken language (single select in the editor).
alter table agents add column language text not null default 'English';
