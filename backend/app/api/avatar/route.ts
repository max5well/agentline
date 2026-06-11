import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { uploadAvatar } from "@/lib/avatars";

// Avatar upload (DESIGN-SPEC §5 stage 2): the app sends a base64 PNG
// (already square-cropped and downscaled), it lands in the public
// "avatars" storage bucket; the returned URL goes on the agent.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { imageBase64 } = await req.json();
  if (!imageBase64)
    return NextResponse.json(
      { error: "imageBase64 required" },
      { status: 400 },
    );

  const bytes = Buffer.from(imageBase64, "base64");
  if (bytes.length > 4 * 1024 * 1024)
    return NextResponse.json({ error: "image too large" }, { status: 413 });

  // The app sends JPEG (photos) — sniff so PNGs keep working too.
  const isPNG = bytes[0] === 0x89 && bytes[1] === 0x50;
  const url = await uploadAvatar(bytes, auth.userId, isPNG ? "image/png" : "image/jpeg");
  if (!url)
    return NextResponse.json({ error: "upload failed" }, { status: 502 });
  return NextResponse.json({ url });
}
