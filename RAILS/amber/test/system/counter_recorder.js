// Loaded by analytics_reduced_motion_test.rb before any page script: every
// text an animated-number counter shows lands in window.counterTexts.
window.counterTexts = []
new MutationObserver((records) => {
  records.forEach((record) => {
    const node = record.target.nodeType === 1 ? record.target : record.target.parentElement
    const counter = node?.closest?.('[data-controller~="animated-number"]')
    if (counter) window.counterTexts.push(counter.textContent.trim())
  })
}).observe(document, { subtree: true, childList: true, characterData: true })
