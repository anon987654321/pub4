// LAUI agent engagement rail — thought / action / speech lanes (deferred)
(function () {
  if (window.__faceAgentHudInit) return
  window.__faceAgentHudInit = true

  const root = document.documentElement
  const hud = document.createElement("aside")
  hud.id = "agent-hud"
  hud.className = "agent-hud"
  hud.setAttribute("aria-label", "Agent activity")
  hud.innerHTML = `
    <div class="agent-hud-lane agent-hud-thought" data-lane="thought"></div>
    <div class="agent-hud-lane agent-hud-action" data-lane="action"></div>
    <div class="agent-hud-lane agent-hud-speech" data-lane="speech"></div>
  `
  document.body.appendChild(hud)

  const lanes = {
    thought: hud.querySelector('[data-lane="thought"]'),
    action: hud.querySelector('[data-lane="action"]'),
    speech: hud.querySelector('[data-lane="speech"]')
  }

  function setLane(name, text) {
    const el = lanes[name]
    if (!el || !text) return
    el.textContent = text
    root.dataset.agentEngagement = name
  }

  window.MASTER_AGENT_PLACEHOLDERS = window.MASTER_AGENT_PLACEHOLDERS || {
    thought: "…",
    action: "…",
    speech: "…"
  }

  function applyPlaceholders() {
    Object.entries(window.MASTER_AGENT_PLACEHOLDERS).forEach(([k, v]) => {
      if (lanes[k] && !lanes[k].textContent) lanes[k].textContent = v
    })
  }

  window.addEventListener("master:runtime-config", () => {
    const modalities = window.MASTER_RUNTIME?.face_research?.modalities
    if (!modalities) return
    modalities.forEach((m) => {
      if (m?.id && m?.placeholder) window.MASTER_AGENT_PLACEHOLDERS[m.id] = m.placeholder
    })
    applyPlaceholders()
  })

  window.addEventListener("master:visual", (event) => {
    const detail = event.detail || {}
    const type = String(detail.type || detail.kind || "").toLowerCase()
    const text = detail.text || detail.message || detail.label || ""
    if (!text) return
    if (type.includes("thought")) setLane("thought", text)
    else if (type.includes("tool") || type.includes("action")) setLane("action", text)
    else if (type.includes("speech") || type.includes("tts") || type.includes("say")) setLane("speech", text)
    else setLane("thought", text)
  })

  applyPlaceholders()
})()