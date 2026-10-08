import "pub4/hotwire"
import "controllers"

if ("periodicSync" in navigator && "serviceWorker" in navigator) {
  navigator.serviceWorker.ready.then(reg => {
    reg.periodicSync?.register("feed-prewarm", { minInterval: 24 * 60 * 60 * 1000 }).catch(() => {})
    reg.periodicSync?.register("badge-refresh", { minInterval: 6 * 60 * 60 * 1000 }).catch(() => {})
  })
}
