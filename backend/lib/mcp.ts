// Minimal MCP client over Streamable HTTP (JSON-RPC 2.0): just enough
// to initialize, list tools, and call one — the handoff path. Handles
// plain-JSON and SSE-framed responses.

interface RPCResult {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  result?: any;
  error?: { message: string };
}

async function rpc(
  url: string,
  authToken: string,
  sessionId: string | null,
  method: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  params: any,
  id: number | null,
): Promise<{ body: RPCResult | null; sessionId: string | null }> {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...(sessionId ? { "Mcp-Session-Id": sessionId } : {}),
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method,
      params,
      ...(id !== null ? { id } : {}),
    }),
  });

  const newSession = res.headers.get("Mcp-Session-Id") ?? sessionId;
  if (id === null) return { body: null, sessionId: newSession }; // notification

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`MCP server ${res.status}: ${text.slice(0, 200)}`);
  }

  const contentType = res.headers.get("Content-Type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const text = await res.text();
    // Last data: line carrying our response id wins.
    for (const line of text.split("\n").reverse()) {
      if (!line.startsWith("data:")) continue;
      try {
        const parsed = JSON.parse(line.slice(5).trim());
        if (parsed.id === id) return { body: parsed, sessionId: newSession };
      } catch {
        /* keep scanning */
      }
    }
    throw new Error("MCP server sent no response on the event stream");
  }
  return { body: await res.json(), sessionId: newSession };
}

export interface MCPTool {
  name: string;
  description?: string;
}

export async function listMCPTools(
  url: string,
  authToken: string,
): Promise<{ serverName: string; tools: MCPTool[] }> {
  const init = await rpc(
    url,
    authToken,
    null,
    "initialize",
    {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "agentline", version: "1.0" },
    },
    1,
  );
  if (init.body?.error) throw new Error(init.body.error.message);
  const serverName = init.body?.result?.serverInfo?.name ?? "MCP server";

  await rpc(
    url,
    authToken,
    init.sessionId,
    "notifications/initialized",
    {},
    null,
  );

  const listed = await rpc(url, authToken, init.sessionId, "tools/list", {}, 2);
  if (listed.body?.error) throw new Error(listed.body.error.message);
  const tools: MCPTool[] = (listed.body?.result?.tools ?? []).map(
    (t: { name: string; description?: string }) => ({
      name: t.name,
      description: t.description,
    }),
  );
  return { serverName, tools };
}

export async function callMCPTool(
  url: string,
  authToken: string,
  toolName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  args: Record<string, any>,
): Promise<void> {
  const init = await rpc(
    url,
    authToken,
    null,
    "initialize",
    {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "agentline", version: "1.0" },
    },
    1,
  );
  if (init.body?.error) throw new Error(init.body.error.message);
  await rpc(
    url,
    authToken,
    init.sessionId,
    "notifications/initialized",
    {},
    null,
  );

  const result = await rpc(
    url,
    authToken,
    init.sessionId,
    "tools/call",
    {
      name: toolName,
      arguments: args,
    },
    2,
  );
  if (result.body?.error) throw new Error(result.body.error.message);
}
