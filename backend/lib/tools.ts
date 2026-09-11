import { supabase } from "@/lib/supabase";
import type { MCPTool } from "@/lib/mcp";

// In-call tools (ADR-7). The MCP tools a user connected are handed to the
// voice provider as function declarations, so the agent can call them
// mid-conversation. Two providers, two schema dialects, one source of
// truth: the tool list cached on the connection row.

export interface CallTools {
  url: string;
  authToken: string;
  tools: MCPTool[];
}

// Both providers accept ^[a-zA-Z0-9_-]{1,64}$ as a function name; MCP
// servers are free to use anything. The mapping is deterministic, so the
// original is recovered by re-sanitizing the cached list — no state.
export function sanitizeToolName(name: string): string {
  const cleaned = name.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64);
  return cleaned.length > 0 ? cleaned : "tool";
}

export function resolveToolName(
  sanitized: string,
  tools: MCPTool[],
): string | null {
  return tools.find((t) => sanitizeToolName(t.name) === sanitized)?.name ?? null;
}

// Loads the user's connected server and the tools they allowed in calls.
// Never throws: a broken or missing connection just means no tools, and a
// call must never fail because of them.
export async function loadCallTools(
  userId: string | null,
): Promise<CallTools | null> {
  if (!userId) return null;
  try {
    const { data } = await supabase()
      .from("mcp_connections")
      .select("url, auth_token, tools_json, call_tools")
      .eq("user_id", userId)
      .maybeSingle();
    if (!data?.url || !Array.isArray(data.tools_json)) return null;

    const all = data.tools_json as MCPTool[];
    const allowed: string[] | null = data.call_tools ?? null;
    const tools = allowed ? all.filter((t) => allowed.includes(t.name)) : all;
    if (tools.length === 0) return null;

    // Providers degrade badly with huge tool lists, and every declaration
    // costs prompt tokens on a latency-sensitive path.
    return {
      url: data.url,
      authToken: data.auth_token ?? "",
      tools: tools.slice(0, 24),
    };
  } catch (e) {
    console.warn("loadCallTools failed (run migration 0015?):", e);
    return null;
  }
}

// JSON Schema keywords both providers accept. Anything else (notably
// $schema, $ref, oneOf, additionalProperties) makes Gemini reject the whole
// setup message, so unknown keys are dropped rather than passed through.
const ALLOWED_KEYS = new Set([
  "type",
  "description",
  "enum",
  "items",
  "properties",
  "required",
  "nullable",
  "format",
]);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function cleanSchema(schema: any, depth = 0): any {
  if (!schema || typeof schema !== "object" || depth > 6) {
    return { type: "string" };
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const out: Record<string, any> = {};
  for (const [key, value] of Object.entries(schema)) {
    if (!ALLOWED_KEYS.has(key)) continue;
    if (key === "properties" && value && typeof value === "object") {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const props: Record<string, any> = {};
      for (const [prop, sub] of Object.entries(value)) {
        props[prop] = cleanSchema(sub, depth + 1);
      }
      out.properties = props;
    } else if (key === "items") {
      out.items = cleanSchema(value, depth + 1);
    } else if (key === "type" && typeof value === "string") {
      out.type = value.toLowerCase();
    } else if (key === "required" && Array.isArray(value)) {
      out.required = value.filter((r) => typeof r === "string");
    } else {
      out[key] = value;
    }
  }
  if (!out.type) out.type = "object";
  // An object schema without properties is rejected by Gemini; give it an
  // empty bag rather than dropping the tool.
  if (out.type === "object" && !out.properties) out.properties = {};
  if (out.type === "object" && out.required) {
    const known = Object.keys(out.properties);
    out.required = (out.required as string[]).filter((r) => known.includes(r));
    if (out.required.length === 0) delete out.required;
  }
  return out;
}

function describe(tool: MCPTool): string {
  return (tool.description ?? `Run the ${tool.name} tool`).slice(0, 900);
}

// OpenAI Realtime: flat function entries inside the session config.
export function toOpenAITools(tools: MCPTool[]) {
  return tools.map((t) => ({
    type: "function" as const,
    name: sanitizeToolName(t.name),
    description: describe(t),
    parameters: cleanSchema(t.inputSchema ?? { type: "object", properties: {} }),
  }));
}

// Gemini Live: one tool entry holding all function declarations. Returned
// to the app, which merges it with googleSearch in its setup message.
export function toGeminiTools(tools: MCPTool[]) {
  return tools.map((t) => ({
    name: sanitizeToolName(t.name),
    description: describe(t),
    parameters: cleanSchema(t.inputSchema ?? { type: "object", properties: {} }),
  }));
}

// Appended to the persona so the agent knows the tools are real actions
// with audible consequences, and keeps talking while one runs.
export function toolInstructions(tools: MCPTool[]): string {
  const names = tools.map((t) => sanitizeToolName(t.name)).join(", ");
  return (
    `\n\nYou can use these tools during the call: ${names}. ` +
    "They act on the caller's real accounts and files, so use them when the caller asks for something they can do, " +
    "and say in one short sentence what you are about to do before you call one. " +
    "Never invent a result: if a tool fails, say so plainly. " +
    "Keep the conversation flowing while a tool runs — a brief 'one second' is better than silence."
  );
}
