export function displayNameFromMetadata(metadata: unknown): string | null {
  if (!metadata || typeof metadata !== "object") return null;
  const values = metadata as Record<string, unknown>;
  for (const key of ["display_name", "full_name", "name", "given_name"]) {
    const value = values[key];
    if (typeof value !== "string") continue;
    const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 80);
    if (cleaned) return cleaned;
  }
  return null;
}
