// MASTER Web UI – chat with command palette and auto‑suggest
(function() {
  const input = document.getElementById("zin");
  const chatLog = document.getElementById("chat-log");
  const statusBar = document.getElementById("status-bar");
  let streaming = false, cursor = null;
  const commands = ["/scan", "/sweep", "/beauty", "/council", "/why", "/undo", "/history", "/model", "/save", "/exit"];
  function addMessage(role, text, withCursor) {
    const div = document.createElement("div");
    div.className = "message " + role;
    div.textContent = text;
    if (withCursor) {
      cursor = document.createElement("span");
      cursor.className = "cursor";
      cursor.textContent = "|";
      div.appendChild(cursor);
    }
    chatLog.appendChild(div);
    div.scrollIntoView();
    return div;
  }
  function showSuggestions() {
    const val = input.value;
    if (!val.startsWith("/")) return;
    const matches = commands.filter(c => c.startsWith(val));
    const box = document.getElementById("suggestions");
    if (matches.length && val !== matches[0]) {
      box.innerHTML = matches.map(c => `<div class="suggestion">${c}</div>`).join("");
      box.style.display = "block";
    } else {
      box.style.display = "none";
    }
  }
  input.addEventListener("input", showSuggestions);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Tab") { e.preventDefault(); acceptFirstSuggestion(); }
    else if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
  });
  function acceptFirstSuggestion() {
    const first = document.querySelector(".suggestion");
    if (first) { input.value = first.textContent + " "; document.getElementById("suggestions").style.display = "none"; }
  }
  async function sendMessage() {
    const text = input.value.trim();
    if (!text || streaming) return;
    addMessage("user", text);
    input.value = "";
    streaming = true;
    const currentDiv = addMessage("assistant", "", true);
    const resp = await fetch("/chat/message", { method: "POST", body: new URLSearchParams({ message: text }) });
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n\n");
      buffer = lines.pop();
      for (const line of lines) {
        if (line.startsWith("data: ")) {
          const data = line.slice(6);
          if (data === "[DONE]") {
            if (cursor) cursor.remove();
            streaming = false;
            break;
          }
          cursor.insertAdjacentText("beforebegin", data.replace(/\\n/g, "\n"));
        }
      }
    }
  }
  async function updateStatus() {
    try {
      const res = await fetch("/chat/metrics");
      const data = await res.json();
      if (statusBar) statusBar.innerHTML = `${data.model} | ${data.tokens} tok | $${data.cost}`;
    } catch(e) {}
  }
  setInterval(updateStatus, 5000);
  updateStatus();
})();
