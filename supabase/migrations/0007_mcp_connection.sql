-- MCP handoff (stage 1): one MCP server per user; the chosen tool
-- receives call data after every call.
create table mcp_connections (
  user_id uuid primary key references auth.users (id),
  url text not null,
  auth_token text not null default '',
  tool_name text,
  server_name text,
  created_at timestamptz not null default now()
);
alter table mcp_connections enable row level security;
