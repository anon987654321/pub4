"use strict";

import { ZONE_NAMES } from '/face3d_geometry.js';

function clamp(v, lo = 0, hi = 1) {
  return Math.max(lo, Math.min(hi, v));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function parseRGB(rgb) {
  if (Array.isArray(rgb)) return rgb;
  return String(rgb || '255,255,255').split(',').map(Number).slice(0, 3);
}

const DEFAULT_PALETTE = Object.freeze({
  shadow: '0,0,0',
  midtone: '90,90,90',
  highlight: '255,255,255',
  accent: '170,210,255'
});

class Face3DCanvasRenderer {
  constructor(canvas, { scale = 0.82, lowRes = true } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false });
    this.scale = scale;
    this.lowRes = lowRes;
    this.width = 0;
    this.height = 0;
    this.dpr = 1;
    this.lpx = document.createElement('canvas');
    this.lctx = this.lpx.getContext('2d', { alpha: false });
    this.fbuf = null;
    this.zbuf = null;
    this.bufSize = 0;
    this.palette = DEFAULT_PALETTE;
    this.dither = 'atkinson';
    this.phosphor = true;
    this.lastLitPixels = 0;
    this.resize();
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.width = w;
    this.height = h;
    this.dpr = dpr;
    this.canvas.width = Math.max(1, Math.floor(w * dpr));
    this.canvas.height = Math.max(1, Math.floor(h * dpr));
    this.canvas.style.width = `${w}px`;
    this.canvas.style.height = `${h}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const lw = this.lowRes ? Math.max(1, w >> 1) : w;
    const lh = this.lowRes ? Math.max(1, h >> 1) : h;
    this.lpx.width = lw;
    this.lpx.height = lh;
    this._ensureBuffers(lw * lh);
  }

  setPalette(palette) {
    this.palette = { ...DEFAULT_PALETTE, ...palette };
  }

  setDither(mode) {
    this.dither = mode === 'bayer' ? 'bayer' : 'atkinson';
  }

  draw(snapshot, state = {}) {
    const lw = this.lpx.width;
    const lh = this.lpx.height;
    this._ensureBuffers(lw * lh);

    const fbuf = this.fbuf;
    const zbuf = this.zbuf;
    const decay = this.phosphor ? 0.80 : 0.0;
    const drain = this.phosphor ? 0.004 : 1.0;
    for (let i = 0; i < fbuf.length; i++) {
      fbuf[i] = Math.max(0, fbuf[i] * decay - drain);
      zbuf[i] = 0;
    }

    const cx = lw * 0.5;
    const cy = lh * 0.50;
    const s = Math.min(lw, lh) * this.scale * 0.48;
    const count = snapshot.count;

    for (let i = 0; i < count; i++) {
      const px = (cx + snapshot.x[i] * s) | 0;
      const py = (cy + snapshot.y[i] * s) | 0;
      if (px < 1 || px >= lw - 1 || py < 1 || py >= lh - 1) continue;

      const depth = snapshot.depth ? snapshot.depth[i] : 0;
      const bright = clamp(snapshot.brightness ? snapshot.brightness[i] : 0.6);
      const zone = snapshot.zone ? snapshot.zone[i] : 0;
      const idx = py * lw + px;
      const val = Math.min(1, bright * (0.50 + depth * 0.18 + 0.45));

      fbuf[idx] = Math.min(1, fbuf[idx] + val);
      zbuf[idx] = zone;

      if (bright > 0.72) {
        fbuf[idx + 1] = Math.min(1, fbuf[idx + 1] + val * 0.32);
        fbuf[idx - 1] = Math.min(1, fbuf[idx - 1] + val * 0.18);
        fbuf[idx + lw] = Math.min(1, fbuf[idx + lw] + val * 0.20);
      }
    }

    this._rasterize(state);
    this.ctx.imageSmoothingEnabled = false;
    this.ctx.fillStyle = '#000';
    this.ctx.fillRect(0, 0, this.width, this.height);
    this.ctx.drawImage(this.lpx, 0, 0, this.width, this.height);
  }

  _ensureBuffers(size) {
    if (this.bufSize === size && this.fbuf && this.zbuf) return;
    this.bufSize = size;
    this.fbuf = new Float32Array(size);
    this.ebuf = new Float32Array(size);
    this.zbuf = new Uint8Array(size);
  }

  _rasterize(state) {
    const lw = this.lpx.width;
    const lh = this.lpx.height;
    const img = this.lctx.getImageData(0, 0, lw, lh);
    const data = img.data;
    const fbuf = this.fbuf;
    const zbuf = this.zbuf;
    this.ebuf.fill(0);

    const accent = parseRGB(this.palette.accent);
    const highlight = parseRGB(this.palette.highlight);
    const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
    let lit = 0;

    for (let y = 0; y < lh; y++) {
      for (let x = 0; x < lw; x++) {
        const idx = y * lw + x;
        const v = clamp(fbuf[idx] + (this.dither === 'atkinson' ? this.ebuf[idx] : 0));
        let on;
        if (this.dither === 'bayer') {
          on = v > bayer[(y & 3) * 4 + (x & 3)] / 16;
        } else {
          on = v >= 0.5;
        }

        const out = idx * 4;
        if (on) {
          lit++;
          // Pure white dithered phosphor pixels — 8-bit monochrome CRT / terminal aesthetic.
          // Shading via Atkinson or Bayer dither only; no zone tints or color.
          data[out] = 255;
          data[out + 1] = 255;
          data[out + 2] = 255;
          data[out + 3] = 255;
        } else {
          data[out] = 0;
          data[out + 1] = 0;
          data[out + 2] = 0;
          data[out + 3] = 255;
        }

        if (this.dither === 'atkinson') {
          const err = (v - (on ? 1 : 0)) * 0.125;
          if (x + 1 < lw) this.ebuf[idx + 1] += err;
          if (x + 2 < lw) this.ebuf[idx + 2] += err;
          if (y + 1 < lh) {
            if (x > 0) this.ebuf[idx + lw - 1] += err;
            this.ebuf[idx + lw] += err;
            if (x + 1 < lw) this.ebuf[idx + lw + 1] += err;
          }
          if (y + 2 < lh) this.ebuf[idx + lw * 2] += err;
        }
      }
    }

    this.lctx.putImageData(img, 0, 0);
    this.lastLitPixels = lit;
  }
}

window.MasterFace3DRenderer = Object.freeze({ Face3DCanvasRenderer });

export { Face3DCanvasRenderer };
