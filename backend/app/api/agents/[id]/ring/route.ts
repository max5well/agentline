import { randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { apnsConfigured, sendVoIPPush, type APNsEnvironment } from "@/lib/apns";
import { requireRingToken } from "@/lib/ring-auth";
import { supabase } from "@/lib/supabase";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

export async function POST(req: NextRequest, context: Context) {
  const auth = await requireRingToken(req);
  if (auth instanceof NextResponse) return auth;

  const { id } = await context.params;
  const body = await req.json().catch(() => null);
  const brief = typeof body?.brief === "string" ? body.brief.trim() : "";
  if (!brief || brief.length > 1_000) {
    return NextResponse.json(
      { error: "brief must be between 1 and 1000 characters" },
      { status: 400 },
    );
  }

  let deadline: string | undefined;
  if (body?.deadline !== undefined && body.deadline !== null) {
    const parsed = typeof body.deadline === "string" ? new Date(body.deadline) : null;
    if (!parsed || Number.isNaN(parsed.getTime())) {
      return NextResponse.json({ error: "deadline must be an ISO date" }, { status: 400 });
    }
    deadline = parsed.toISOString();
  }

  const { data: agent } = await supabase()
    .from("agents")
    .select("id, name, emoji")
    .eq("id", id)
    .eq("user_id", auth.userId)
    .maybeSingle();
  if (!agent) return NextResponse.json({ error: "agent not found" }, { status: 404 });
  if (!apnsConfigured()) {
    return NextResponse.json({ error: "incoming calls are not configured" }, { status: 503 });
  }

  const { data: allowed, error: limitError } = await supabase().rpc(
    "consume_agent_ring_rate_limit",
    { p_user_id: auth.userId, p_limit: 6, p_window_seconds: 60 },
  );
  if (limitError) {
    console.error("ring rate limit failed", limitError.message);
    return NextResponse.json({ error: "ring unavailable" }, { status: 503 });
  }
  if (!allowed) {
    return NextResponse.json({ error: "too many ring requests" }, { status: 429 });
  }

  const { data: devices, error: devicesError } = await supabase()
    .from("voip_devices")
    .select("token, environment")
    .eq("user_id", auth.userId);
  if (devicesError) {
    return NextResponse.json({ error: devicesError.message }, { status: 500 });
  }
  if (!devices?.length) {
    return NextResponse.json(
      { error: "no iPhone is registered for incoming calls" },
      { status: 409 },
    );
  }

  const callId = randomUUID();
  const results = await Promise.allSettled(
    devices.map(async (device) => {
      const result = await sendVoIPPush(
        device.token,
        device.environment as APNsEnvironment,
        {
          callId,
          agentId: agent.id,
          agentName: agent.name,
          agentEmoji: agent.emoji,
          brief,
          deadline,
        },
      );
      if (
        !result.ok &&
        (result.status === 410 || result.reason === "BadDeviceToken" || result.reason === "Unregistered")
      ) {
        await supabase().from("voip_devices").delete().eq("token", device.token);
      }
      return result;
    }),
  );

  const delivered = results.filter(
    (result) => result.status === "fulfilled" && result.value.ok,
  ).length;
  if (delivered === 0) {
    const reasons = results.map((result) =>
      result.status === "fulfilled"
        ? result.value.reason ?? `APNs ${result.value.status}`
        : result.reason instanceof Error
          ? result.reason.message
          : "push failed",
    );
    console.error("all VoIP pushes failed", reasons);
    return NextResponse.json({ error: "could not reach a registered iPhone" }, { status: 502 });
  }

  await supabase()
    .from("events")
    .insert({
      user_id: auth.userId,
      type: "agent_ring",
      meta: { agent_id: agent.id, call_id: callId, delivered, devices: devices.length },
    })
    .then(({ error }) => {
      if (error) console.warn("agent_ring event insert failed", error.message);
    });

  return NextResponse.json({ ok: true, callId, delivered }, { status: 202 });
}
