const byId = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);

function buildState() {
  let state = {};
  try { state = JSON.parse(byId("state").value); } catch (e) { state = {}; }
  state.mix_ = Object.assign({}, state.mix_ || {}, {
    style: byId("style").value,
    bars: Number(byId("bars").value) || 12
  });
  return {
    name: byId("name").value,
    style: byId("style").value,
    bars: Number(byId("bars").value) || 12,
    notes: byId("notes").value,
    state
  };
}

function encodeHash() {
  const payload = buildState();
  return btoa(unescape(encodeURIComponent(JSON.stringify({
    pat_: payload.state.pat_ || {},
    aud_: payload.state.aud_ || {},
    mix_: payload.state.mix_ || {},
    name: payload.name,
    style: payload.style,
    bars: payload.bars
  }))));
}

byId("btn-copy").addEventListener("click", () => {
  try {
    const hash = encodeHash();
    history.replaceState(null, "", location.pathname + location.search + "#" + hash);
    navigator.clipboard.writeText(hash).then(() => {
      byId("status").textContent = "Hash copied and set in URL.\nPaste JSON into the playlist sketch form, then Render.";
      byId("status").className = "status ok";
    });
  } catch (e) {
    byId("status").textContent = "Encode failed: " + e.message;
    byId("status").className = "status err";
  }
});

byId("btn-decode").addEventListener("click", () => {
  const raw = location.hash.replace(/^#/, "");
  if (!raw) { byId("status").textContent = "No hash in URL."; return; }
  try {
    const json = JSON.parse(decodeURIComponent(escape(atob(raw))));
    if (json.name) byId("name").value = json.name;
    if (json.style) byId("style").value = json.style;
    if (json.bars) byId("bars").value = json.bars;
    byId("state").value = JSON.stringify({
      pat_: json.pat_ || {},
      aud_: json.aud_ || {},
      mix_: json.mix_ || { style: json.style || "dilla", bars: json.bars || 12 }
    }, null, 2);
    byId("status").textContent = "Loaded state from URL hash.";
    byId("status").className = "status ok";
  } catch (e) {
    byId("status").textContent = "Decode failed: " + e.message;
    byId("status").className = "status err";
  }
});

if (params.get("playlist_id")) {
  byId("link-playlist").href = "/playlists/" + params.get("playlist_id");
  byId("link-playlist").textContent = "Open playlist #" + params.get("playlist_id");
}
if (location.hash) byId("btn-decode").click();
