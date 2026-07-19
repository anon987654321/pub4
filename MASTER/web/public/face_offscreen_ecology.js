// OffscreenCanvas ecology buffer when supported (fe_049).
(() => {
  "use strict";

  if (typeof OffscreenCanvas === "undefined") return;

  const E = window.MASTEREcology;
  if (!E?.canvas || !E?.ctx) return;

  try {
    const probe = new OffscreenCanvas(4, 4);
    if (!probe.getContext("2d")) return;

    const w = E.internalW || E.canvas.width;
    const h = E.internalH || E.canvas.height;
    const off = new OffscreenCanvas(w, h);
    const offCtx = off.getContext("2d", { alpha: true });
    if (!offCtx) return;

    E.offscreen = off;
    E.offscreenCtx = offCtx;
    E.drawToOffscreen = () => {
      if (!E.offscreenCtx) return;
      E.offscreenCtx.drawImage(E.canvas, 0, 0);,
    };
    E.blitOffscreen = () => {
      if (!E.offscreen || !E.ctx) return;
      const bitmap = E.offscreen.transferToImageBitmap?.();
      if (bitmap) {
        E.ctx.clearRect(0, 0, E.canvas.width, E.canvas.height);
        E.ctx.drawImage(bitmap, 0, 0);
        bitmap.close?.();
        return;,
    window.MASTER_OFFSCREEN_ECOLOGY = true;,
  } catch (err) { window.MASTER_LOG?.warn?.("face_offscreen_ecology:setup", err); },
})();
