// Keeps <meta name="theme-color"> on the theme the page shows: html[data-theme]
// when the theme toggle or the head bootstrap set one, prefers-color-scheme
// otherwise. Colours come from data-light-color / data-dark-color.
export function bootThemeMeta() {
  const meta = document.querySelector('meta[name="theme-color"]')
  if (!meta) return

  const light = meta.dataset.lightColor || meta.content
  const dark = meta.dataset.darkColor || meta.content
  const mq = window.matchMedia("(prefers-color-scheme: dark)")
  const root = document.documentElement
  const apply = () => {
    const chosen = root.dataset.theme
    meta.content = (chosen ? chosen === "dark" : mq.matches) ? dark : light
  }

  apply()
  if (mq.addEventListener) mq.addEventListener("change", apply)
  else mq.addListener(apply)
  new MutationObserver(apply).observe(root, { attributes: true, attributeFilter: [ "data-theme" ] })
}
