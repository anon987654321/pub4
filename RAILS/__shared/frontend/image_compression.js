// A phone photo arrives at 4–12 MB while every server variant is at most
// 1,200px on its long edge (Post's hero), so most of an upload was bytes the
// server threw away after carrying them over 4G. Re-encode in the browser
// before the direct upload, and never hand back anything larger than the
// original: a failure, an unsupported format or a bigger result all keep the
// file the person picked, so compression can slow nothing and block nothing.
//
// Decoding through createImageBitmap bakes the EXIF orientation into the
// pixels and drops the metadata, GPS included.

export const MAX_EDGE = 1600
export const QUALITY = 0.85

// Animated GIFs would lose their frames and SVG is not a raster.
const PASS_THROUGH = new Set(["image/gif", "image/svg+xml"])

export function compressible(file) {
  return Boolean(file?.type?.startsWith("image/")) && !PASS_THROUGH.has(file.type)
}

// The largest size within maxEdge on both sides, never upscaled.
export function fitWithin(width, height, maxEdge = MAX_EDGE) {
  const scale = Math.min(1, maxEdge / Math.max(width, height))
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) }
}

export function smaller(original, candidate) {
  return candidate && candidate.size < original.size ? candidate : original
}

export async function compressImage(file, { maxEdge = MAX_EDGE, quality = QUALITY } = {}) {
  if (!compressible(file) || typeof createImageBitmap !== "function" || typeof document === "undefined") return file

  try {
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const { width, height } = fitWithin(bitmap.width, bitmap.height, maxEdge)
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    canvas.getContext("2d").drawImage(bitmap, 0, 0, width, height)
    bitmap.close?.()

    const blob = await encode(canvas, quality, file.type)
    if (!blob) return file

    const stem = file.name.replace(/\.[^.]+$/, "") || "photo"
    const extension = blob.type === "image/webp" ? "webp" : "jpg"
    return smaller(file, new File([blob], `${stem}.${extension}`, { type: blob.type, lastModified: file.lastModified }))
  } catch (_) {
    return file
  }
}

// WebP where the browser encodes it. A canvas that cannot answers PNG instead of
// failing, so the type is checked; JPEG is the fallback except for a PNG, whose
// transparency JPEG would flatten.
async function encode(canvas, quality, originalType) {
  const webp = await toBlob(canvas, "image/webp", quality)
  if (webp?.type === "image/webp") return webp
  if (originalType === "image/png") return null

  const jpeg = await toBlob(canvas, "image/jpeg", quality)
  return jpeg?.type === "image/jpeg" ? jpeg : null
}

function toBlob(canvas, type, quality) {
  return new Promise((resolve) => canvas.toBlob(resolve, type, quality))
}
