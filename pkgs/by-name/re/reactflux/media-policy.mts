// Keep API connections same-origin. Safari can use its native HLS engine;
// other browsers get a usable link instead of a player blocked by the CSP.
export const getExternalHlsFallback = (
  source: unknown,
  mimeType: string | null | undefined,
  origin: string,
  nativeHls: boolean,
): string | null => {
  if (nativeHls || typeof source !== "string" || !source) return null;
  let url;
  try {
    url = new URL(source, origin);
  } catch {
    return null;
  }
  if (!["http:", "https:"].includes(url.protocol)) return null;
  const isHls =
    /mpegurl/i.test(mimeType || "") || /\.m3u8$/i.test(url.pathname);
  return isHls && url.origin !== origin ? url.href : null;
};

// Inspect the publisher URL inside Miniflux's signed media proxy only for
// rendition metadata. Callers must still render the exact supplied proxy URL.
export const getImageUrlMetadata = (source: string): URL | null => {
  try {
    const url = new URL(source, "https://reader.invalid");
    const proxy = /\/proxy\/[A-Za-z0-9_-]{43}=?\/([A-Za-z0-9_=-]+)$/.exec(
      url.pathname,
    );
    if (proxy?.[1]) {
      const decoded = new URL(
        atob(proxy[1].replaceAll("-", "+").replaceAll("_", "/")),
      );
      if (["https:", "http:"].includes(decoded.protocol)) return decoded;
    }
    return url;
  } catch {
    return null;
  }
};

// Keep publisher-signed URLs intact. Prefer a supplied larger rendition of the
// same image, capped at 1024 pixels; never choose a different attachment.
export const chooseCoverImage = (
  images: readonly { url: string }[],
): string | null => {
  const first = images[0]?.url;
  if (!first) return null;
  try {
    const base = getImageUrlMetadata(first);
    if (!base) return first;
    let best = first;
    let bestWidth = Number(base.searchParams.get("width")) || 0;
    for (const image of images.slice(1)) {
      const candidate = getImageUrlMetadata(image.url);
      if (!candidate) continue;
      const width = Number(candidate.searchParams.get("width"));
      if (
        candidate.origin === base.origin &&
        candidate.pathname === base.pathname &&
        width > bestWidth &&
        width <= 1024
      ) {
        best = image.url;
        bestWidth = width;
      }
    }
    return best;
  } catch {
    return first;
  }
};
