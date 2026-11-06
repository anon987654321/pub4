// The /api/key page shows a new key once. The button stays hidden without
// script, and without a clipboard, so it never offers what it cannot do.
const button = document.querySelector('[data-copy-target]');
const source = button && document.getElementById(button.dataset.copyTarget);
if (button && source && navigator.clipboard) {
  button.hidden = false;
  button.addEventListener('click', async () => {
    await navigator.clipboard.writeText(source.textContent);
    button.textContent = button.dataset.copied;
  });
}
