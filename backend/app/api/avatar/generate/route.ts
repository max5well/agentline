import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { uploadAvatar } from "@/lib/avatars";

// Generated avatars (DESIGN-SPEC §5 source 3): two variants per
// request via gpt-image-1, stored in the avatars bucket.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { description } = await req.json();
  if (!description)
    return NextResponse.json(
      { error: "description required" },
      { status: 400 },
    );

  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-image-1",
      prompt:
        `Circular app avatar portrait of: ${description}. ` +
        "Friendly, modern flat illustration style, head and shoulders, centered, plain solid background.",
      n: 2,
      size: "1024x1024",
      quality: "low",
    }),
  });
  if (!res.ok) {
    console.error("image generation failed", res.status, await res.text());
    return NextResponse.json({ error: "generation failed" }, { status: 502 });
  }

  const body = await res.json();
  const urls: string[] = [];
  for (const image of body.data ?? []) {
    if (!image.b64_json) continue;
    const url = await uploadAvatar(
      Buffer.from(image.b64_json, "base64"),
      auth.userId,
    );
    if (url) urls.push(url);
  }
  if (urls.length === 0)
    return NextResponse.json({ error: "generation failed" }, { status: 502 });
  return NextResponse.json({ urls });
}
