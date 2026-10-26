// The phone face's script. face.html is served by the bridge itself
// (bin/master-mobile bridge), so every call goes to the page's own origin.
(function () {
  "use strict";

  const face = document.getElementById("face");
  const statusText = document.getElementById("status-text");
  const log = document.getElementById("log");
  const form = document.getElementById("bar");
  const input = document.getElementById("input");
  const listenButton = document.getElementById("listen");

  function request(method, path, body) {
    return fetch(path, {
      method: method,
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    }).then(function (response) {
      return response.json().then(function (json) {
        if (!response.ok || json.ok === false) throw new Error(json.error || response.statusText);
        return json;
      });
    });
  }

  function setMode(mode) {
    face.dataset.mode = mode;
    face.setAttribute("aria-label", "MASTER face, " + mode);
    statusText.textContent = mode;
  }

  function addLine(role, text) {
    const line = document.createElement("div");
    const prefix = { user: "user: ", master: "master: ", sys: "" }[role];
    line.className = { user: "u", master: "m", sys: "sys" }[role];
    line.textContent = prefix + text;
    log.appendChild(line);
    log.scrollTop = log.scrollHeight;
  }

  function failed(error) {
    setMode("error");
    addLine("sys", error.message);
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    addLine("user", text);
    input.value = "";
    setMode("thinking");
    request("POST", "/utterance", { text: text }).then(function (json) {
      addLine("master", json.reply || "(no reply)");
      setMode("idle");
    }).catch(failed);
  });

  // One press, one utterance: the phone listens until speech-to-text returns, then answers aloud.
  listenButton.addEventListener("click", function () {
    listenButton.disabled = true;
    setMode("listening");
    request("POST", "/listen").then(function (json) {
      addLine("user", json.heard);
      addLine("master", json.reply);
      setMode("idle");
    }).catch(failed).finally(function () {
      listenButton.disabled = false;
    });
  });

  setMode("idle");
  request("GET", "/health").then(function () {
    addLine("sys", "bridge connected");
  }).catch(function () {
    addLine("sys", "bridge offline: run bin/master-mobile bridge");
  });
})();
