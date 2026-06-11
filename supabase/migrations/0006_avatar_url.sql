-- Photo / generated avatars (DESIGN-SPEC §5 stage 2), stored in the
-- public "avatars" storage bucket.
alter table agents add column avatar_url text;
