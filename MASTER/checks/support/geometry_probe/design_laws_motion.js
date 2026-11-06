// The motion phase of the design-book Laws' probe (design_laws.js must load first): DOM
// mutations and the luminance of every large painted area, sampled each frame with no input,
// for AUTO_MOTION_PAUSABLE and FLASH_THRESHOLD.
(() => {
  const { paint, shown, keyOf } = window.__designLaws.helpers;

  const linear = (value) => {
    const channel = value / 255;
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  };
  const luminance = ([red, green, blue]) => (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue));

  const sampleColour = (el) => {
    if (el.tagName !== 'CANVAS') return paint(getComputedStyle(el).backgroundColor);
    try {
      const data = el.getContext('2d')?.getImageData(el.width >> 1, el.height >> 1, 1, 1).data;
      return data ? [data[0], data[1], data[2], 1] : [0, 0, 0, 0];
    } catch (error) {
      return [0, 0, 0, 0];
    }
  };

  const LARGE = 0.25 * 341 * 256;
  const large = () => Array.from(document.querySelectorAll('body, body *')).filter((el) => {
    const box = el.getBoundingClientRect();
    return box.width * box.height >= LARGE && shown(el, getComputedStyle(el));
  }).slice(0, 60);

  const PAUSE = 'button[aria-pressed], [data-action*="pause"], button[aria-label*="ause"], button.pause';

  // DOM mutations and painted-ground changes with no input, for the motion and flash Laws.
  const watch = (ms) => new Promise((resolve) => {
    let changes = 0;
    let last = 0;
    const start = performance.now();
    const observer = new MutationObserver((list) => {
      changes += list.length;
      last = performance.now() - start;
    });
    observer.observe(document.body, { subtree: true, attributes: true, childList: true, characterData: true });
    const big = large();
    const samples = big.map(() => []);
    const frame = () => {
      const at = performance.now() - start;
      big.forEach((el, i) => {
        const seen = Number.parseFloat(getComputedStyle(el).opacity);
        const opacity = Number.isNaN(seen) ? 0 : seen;
        samples[i].push([Math.round(at), Math.round(luminance(sampleColour(el)) * opacity * 1000) / 1000]);
      });
      if (at < ms) return requestAnimationFrame(frame);
      observer.disconnect();
      const surfaces = big.map((el, i) => ({ key: keyOf(el), samples: samples[i] }));
      resolve({ changes, last_change: last, window: ms, pause: !!document.querySelector(PAUSE), surfaces });
      return null;
    };
    requestAnimationFrame(frame);
  });

  window.__designLaws.watch = watch;
  return true;
})()
