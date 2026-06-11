// Storage upload for avatars (public bucket created 2026-06-13).
export async function uploadAvatar(
  bytes: Buffer,
  userId: string,
  contentType: "image/png" | "image/jpeg" = "image/png",
): Promise<string | null> {
  const ext = contentType === "image/jpeg" ? "jpg" : "png";
  const path = `${userId}/${crypto.randomUUID()}.${ext}`;
  const base = process.env.SUPABASE_URL!;
  const res = await fetch(`${base}/storage/v1/object/avatars/${path}`, {
    method: "POST",
    headers: {
      // New-format (sb_secret_) keys aren't JWTs — storage wants them in
      // the apikey header, not just as a Bearer token.
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": contentType,
      "x-upsert": "true",
    },
    body: new Uint8Array(bytes),
  });
  if (!res.ok) {
    console.error("avatar upload failed", res.status, await res.text());
    return null;
  }
  return `${base}/storage/v1/object/public/avatars/${path}`;
}
