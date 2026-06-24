(() => {
  "use strict";

  const SHORTCUTS = [
    ["Ctrl/Cmd+K", "Command palette"],
    ["Ctrl/Cmd+Shift+H", "Toggle history sidebar"],
    ["Ctrl/Cmd+Shift+E", "Export session markdown"],
    ["/", "Open palette from empty input"],
    ["?", "Shortcut cheat sheet"],
    ["Esc", "Close palette / interrupt stream"],
    ["Space (hold)", "Push-to-talk"],
    ["t", "Toggle TTS mute"],
    ["m", "Toggle microphone"],
    ["Ctrl+[ / ]", "TTS playback rate"]
  ];

  function ensureDialog() {
    let el = document.getElementById("shortcut-sheet");
    if (el) return el;
    el = document.createElement("dialog");
    el.id = "shortcut-sheet";
    el.setAttribute("aria-label", "Keyboard shortcuts");
    el.innerHTML = '<form method="dialog"><header><strong>shortcuts</strong></header><table></table><button value="close">close</button></form>';
    document.body.appendChild(el);
    const table = el.querySelector("table");
    SHORTCUTS.forEach(([key, desc]) => {
      const row = document.createElement("tr");
      row.innerHTML = `<td><kbd>${key}</kbd></td><td>${desc}</td>`;
      table.appendChild(row);
    });
    return el;
  }

  function openSheet() {
    const dialog = ensureDialog();
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "open");
    window.MASTERVisual?.event?.("shortcuts:open", { topology: "neural", entropy: 0.1, confidence: 0.92, mode: "help" });
  }

  function closeSheet() {
    const dialog = document.getElementById("shortcut-sheet");
    if (!dialog) return;
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
  }

  document.addEventListener("keydown", (ev) => {
    if (ev.key === "?" && document.activeElement?.id !== "zin") {
      ev.preventDefault();
      openSheet();
    }
  });

  window.MASTERShortcuts = { open: openSheet, close: closeSheet, list: SHORTCUTS };
})();