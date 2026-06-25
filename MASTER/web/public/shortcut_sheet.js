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
    ["f", "Focus face canvas"],
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

  function faceAck(kind) {
    const face = window.MASTER_FACE;
    const st = face?.State;
    if (!st) return;
    st.pulse = Math.max(st.pulse || 0, 0.32);
    st.questionPulse = Math.max(st.questionPulse || 0, 0.4);
    window.MASTERVisual?.event?.(`shortcut:${kind}`, { topology: "papua-mask", entropy: 0.14, confidence: 0.9, mode: "ack" });
  }

  document.addEventListener("keydown", (ev) => {
    const tag = document.activeElement?.tagName;
    const inInput = tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.id === "zin";
    if (ev.key === "?" && !inInput) {
      ev.preventDefault();
      openSheet();
      faceAck("help");
      return;
    }
    if (inInput) return;
    if (ev.key === "t" || ev.key === "T") { faceAck("mute"); return; }
    if (ev.key === "m" || ev.key === "M") { faceAck("mic"); return; }
    if (ev.key === "f" || ev.key === "F") {
      const canvas = document.getElementById("face");
      canvas?.focus?.();
      faceAck("focus");
      window.MASTERVisual?.event?.("shortcut:focus", { topology: "papua-mask", entropy: 0.1, confidence: 0.92, mode: "focus" });
      return;
    }
    if (ev.key === "Escape") { faceAck("escape"); return; }
    if ((ev.metaKey || ev.ctrlKey) && ev.key === "[") { faceAck("rate_down"); return; }
    if ((ev.metaKey || ev.ctrlKey) && ev.key === "]") { faceAck("rate_up"); return; }
  });

  window.MASTERShortcuts = { open: openSheet, close: closeSheet, list: SHORTCUTS };
})();