import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";

export async function POST(req: NextRequest) {
  const { refreshToken } = await req.json();
  if (!refreshToken)
    return NextResponse.json(
      { error: "refreshToken required" },
      { status: 400 },
    );

  const { data, error } = await supabase().auth.refreshSession({
    refresh_token: refreshToken,
  });
  if (error || !data.session || !data.user)
    return NextResponse.json({ error: "session expired" }, { status: 401 });
  return sessionResponse(data.session, data.user);
}
