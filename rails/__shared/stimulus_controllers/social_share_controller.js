// Social Share Stimulus Controller
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, title: String, text: String }

  connect() {
    this.urlValue = this.urlValue || window.location.href
    this.titleValue = this.titleValue || document.title
  }

  async share(event) {
    const platform = event.currentTarget.dataset.platform
    platform === "native" && navigator.share 
      ? await this.shareNative() 
      : this.sharePlatform(platform)
  }

  async shareNative() {
    try {
      await navigator.share({
        title: this.titleValue,
        text: this.textValue,
        url: this.urlValue
      })
    } catch (error) {
      if (error.name !== 'AbortError') console.error('Share failed:', error)
    }
  }

  sharePlatform(platform) {
    const url = encodeURIComponent(this.urlValue)
    const title = encodeURIComponent(this.titleValue)
    const urls = {
      twitter: `https://twitter.com/intent/tweet?url=${url}&text=${title}`,
      facebook: `https://www.facebook.com/sharer/sharer.php?u=${url}`,
      linkedin: `https://www.linkedin.com/sharing/share-offsite/?url=${url}`
    }
    if (urls[platform]) window.open(urls[platform], '_blank', 'width=600,height=400')
  }

  copyLink(event) {
    navigator.clipboard.writeText(this.urlValue).then(() => {
      const btn = event.currentTarget
      const orig = btn.textContent
      btn.textContent = "Copied!"
      setTimeout(() => btn.textContent = orig, 2000)
    })
  }
}
