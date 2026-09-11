-- In-call tools (ADR-7): the agent may use the user's connected MCP tools
-- during the call, not only receive the digest after it.

-- Per-agent opt-in. Off by default: an agent that got no tools yesterday
-- must not silently gain them.
alter table agents
  add column if not exists tools_enabled boolean not null default false;

-- The server's tool list, cached when the user connects it. Token minting
-- reads this instead of calling the MCP server, so enabling tools adds no
-- latency to the start of a call.
alter table mcp_connections
  add column if not exists tools_json jsonb;

-- Subset the user allows in calls; null = every tool the server exposes.
-- Distinct from tool_name, which stays the single digest-push target.
alter table mcp_connections
  add column if not exists call_tools text[];
