// Council multi-face lanes — left/center/right persona indicators (web_007).
(() => {
  "use strict";

  const LANES = [
    { id: "left", personas: ["Architect", "Mentor"], x: "18%" },
    { id: "center", personas: ["Pragmatist", "User"], x: "50%" },
    { id: "right", personas: ["Skeptic", "Security"], x: "82%" }
  ];

  let strip = null;
  let activeCouncil = false;

  function ensureStrip() {
    if (strip) return strip;
    strip = document.createElement("div");
    strip.id = "council-multi-face";
    strip.className = "council-multi-face";
    strip.setAttribute("aria-hidden", "true");
    strip.innerHTML = LANES.map((lane) =>
      `<span class="council-lane" data-lane="${lane.id}" style="left:${lane.x}"></span>`
    ).join("");
    document.body.appendChild(strip);
    return strip;
  }

  function setLaneActive(lane, persona) {
    const el = ensureStrip().querySelector(`[data-lane="${lane}"]`);
    if (!el) return;
    el.dataset.persona = persona || "";
    el.dataset.active = "1";
    el.classList.add("pulse");
    setTimeout(() => el.classList.remove("pulse"), 900);
  }

  function clearLanes() {
    if (!strip) return;
    strip.querySelectorAll(".council-lane").forEach((el) => {
      delete el.dataset.active;
      delete el.dataset.persona;
    });
    strip.dataset.visible = "0";
    activeCouncil = false;
    document.body.dataset.councilMulti = "";
  }

  function personaLane(persona) {
    const name = String(persona || "");
    const hit = LANES.find((lane) => lane.personas.includes(name));
    return hit?.id || "center";
  }

  function onCouncilStart() {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("council_multi_face")) return;
    activeCouncil = true;
    ensureStrip().dataset.visible = "1";
    document.body.dataset.councilMulti = "1";
    window.MASTERVisual?.event?.("council:multi:start", { topology: "papua-mask", entropy: 0.38, confidence: 0.62, mode: "council" });
  }

  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    const name = String(d.name || d.mode || "");
    if (/council:deliberation|council:start/i.test(name)) onCouncilStart();
    if (/council:(?:vote|speech|end)|tribunal:rendered/i.test(name)) clearLanes();
  });

  window.addEventListener("tts:style:active", (ev) => {
    const persona = ev.detail?.persona;
    if (!persona || !activeCouncil) return;
    setLaneActive(personaLane(persona), persona);
  });

  window.MASTERCouncilMulti = Object.freeze({
    personaLane,
    setLaneActive,
    clearLanes,
    onCouncilStart
  });
})();
