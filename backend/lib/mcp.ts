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
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  inputSchema?: any;
}

export interface CallDigestPayload {
  title: string;
  date: string;
  summary: string;
  actionItems: string[];
  transcript: string;
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
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (t: { name: string; description?: string; inputSchema?: any }) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
    }),
  );
  return { serverName, tools };
}

// Schema-aware push: most MCP tools expect their own argument shape
// (e.g. {path, content}), not ours. Read the tool's inputSchema and let
// a small model translate the digest into it; tools without a usable
// schema get the default shape.
export async function pushDigestToMCPTool(
  url: string,
  authToken: string,
  toolName: string,
  digest: CallDigestPayload,
): Promise<void> {
  const { tools } = await listMCPTools(url, authToken);
  const tool = tools.find((t) => t.name === toolName);
  const properties = tool?.inputSchema?.properties;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let args: Record<string, any> = { ...digest };
  if (properties && Object.keys(properties).length > 0) {
    const mapped = await mapDigestToSchema(digest, tool.inputSchema, toolName);
    if (mapped) args = mapped;
  }
  await callMCPTool(url, authToken, toolName, args);
}

async function mapDigestToSchema(
  digest: CallDigestPayload,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  schema: any,
  toolName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<Record<string, any> | null> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            `You translate a voice-call digest into valid arguments for the MCP tool "${toolName}". ` +
            "Reply with a single JSON object that satisfies the tool's JSON schema exactly — " +
            "required fields present, no extra fields, correct types. " +
            "Fit the digest content naturally (e.g. a 'content'/'body'/'text' field gets a markdown document with summary, action items and transcript; " +
            "a 'path'/'name'/'title' field gets a filename-safe title with date). Do not invent data beyond the digest.",
        },
        {
          role: "user",
          content: `Tool input schema:\n${JSON.stringify(schema)}\n\nCall digest:\n${JSON.stringify(digest)}`,
        },
      ],
    }),
  });
  if (!res.ok) {
    console.error("schema mapping failed", res.status, await res.text());
    return null;
  }
  const body = await res.json();
  try {
    return JSON.parse(body.choices[0].message.content);
  } catch {
    return null;
  }
}

export async function callMCPTool(
  url: string,
  authToken: string,
  toolName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  args: Record<string, any>,
): Promise<void> {
  await callMCPToolForResult(url, authToken, toolName, args);
}

// Same call, but the tool's output comes back as text — the in-call path
// (ADR-7), where the result is spoken to the caller. One initialize per
// call: MCP sessions are per-connection and a voice call fires a tool
// every few turns at most, so pooling would buy little and leak sessions.
export async function callMCPToolForResult(
  url: string,
  authToken: string,
  toolName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  args: Record<string, any>,
): Promise<string> {
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
  return flattenContent(result.body?.result);
}

// MCP returns a content array of typed blocks. The model only needs the
// readable part; non-text blocks are named so it can say what came back
// instead of pretending nothing did.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function flattenContent(result: any): string {
  if (!result) return "Done.";
  if (result.isError) {
    const message = flattenContent({ content: result.content });
    throw new Error(message || "Tool reported an error");
  }
  const content = result.content;
  if (!Array.isArray(content)) {
    return typeof result === "string" ? result : JSON.stringify(result);
  }
  const parts = content
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    .map((block: any) => {
      if (typeof block?.text === "string") return block.text;
      if (block?.type) return `[${block.type} content]`;
      return "";
    })
    .filter(Boolean);
  return parts.join("\n").trim() || "Done.";
}
