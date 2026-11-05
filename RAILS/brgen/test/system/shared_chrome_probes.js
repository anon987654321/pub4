// Probes shared_chrome_behaviour_test.rb runs in the page. One function per
// question, so the Ruby side reads as the behaviour it asserts.
window.sharedChromeProbes = {
  // The transition timing a fresh .button computes to.
  buttonTiming() {
    const probe = document.createElement("button")
    probe.className = "button"
    document.body.append(probe)
    const value = getComputedStyle(probe).transitionTimingFunction
    probe.remove()
    return value
  },

  // The media condition the .button:hover rule sits under, null when it sits
  // under none, "missing" when no sheet has the rule.
  hoverCondition() {
    const walk = (rules, condition) => {
      for (const rule of rules) {
        if (rule.selectorText === ".button:hover") return condition
        if (!rule.cssRules) continue

        const found = walk(rule.cssRules, rule.conditionText ?? condition)
        if (found !== undefined) return found
      }
      return undefined
    }
    for (const sheet of document.styleSheets) {
      let found
      try {
        found = walk(sheet.cssRules, null)
      } catch (_error) {
        continue
      }
      if (found !== undefined) return found
    }
    return "missing"
  },

  fontFamilies() {
    return [ ...document.fonts ].map((face) => face.family.replaceAll('"', ""))
  },

  // Counts the draft PATCHes autosave sends, and lets the test hide the tab and
  // type into the form.
  watchAutosave() {
    window.autosavePatches = 0
    const send = window.fetch
    window.fetch = (url, options = {}) => {
      const method = (options.method || "").toUpperCase()
      if (method === "PATCH" && String(url).includes("/drafts/")) window.autosavePatches += 1
      return send(url, options)
    }
  },

  hideTab(hidden) {
    const state = hidden ? "hidden" : "visible"
    Object.defineProperty(document, "hidden", { configurable: true, get: () => hidden })
    Object.defineProperty(document, "visibilityState", { configurable: true, get: () => state })
    document.dispatchEvent(new Event("visibilitychange"))
  },

  typeDraft() {
    const form = document.querySelector("form[data-controller~='autosave']")
    form.dispatchEvent(new Event("input", { bubbles: true }))
  },
}
