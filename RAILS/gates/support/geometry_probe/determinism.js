(() => {
  let seed = 0x2545F491;
  Math.random = () => {
    seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
    return ((seed >>> 0) % 1000000) / 1000000;
  };
  const freeze = () => {
    const style = document.createElement('style');
    style.setAttribute('data-gate-determinism', '');
    style.textContent = `*,*::before,*::after{
      animation-duration:0s !important;animation-delay:0s !important;
      animation-iteration-count:1 !important;
      transition-duration:0s !important;transition-delay:0s !important;
      caret-color:transparent !important;scroll-behavior:auto !important;}`;
    (document.head || document.documentElement).appendChild(style);
  };
  if (document.head) freeze();
  else document.addEventListener('DOMContentLoaded', freeze, { once: true });
})();
