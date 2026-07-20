// Syncs <meta name="theme-color"> with prefers-color-scheme using data-light-color / data-dark-color.
export function bootThemeMeta() {
  const meta = document.querySelector('meta[name="theme-color"]')
  if (!meta) return

  const light = meta.dataset.lightColor || meta.content
  const dark = meta.dataset.darkColor || meta.content
  const mq = window.matchMedia("(prefers-color-scheme: dark)")
  const apply = () => { meta.content = mq.matches ? dark : light }

  apply()
  if (mq.addEventListener) mq.addEventListener("change", apply)
  else mq.addListener(apply)
}
