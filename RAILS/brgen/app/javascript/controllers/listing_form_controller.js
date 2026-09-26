import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "section", "stepLink", "photoHint", "videoPreview", "locationStatus",
    "reviewCover", "reviewTitle", "reviewPrice", "reviewCondition",
    "reviewLocation", "reviewSource", "draftStatus"
  ]

  connect() {
    this.step = 0
    this.mediaQuery = window.matchMedia("(max-width: 767px)")
    this.onViewport = () => this.render()
    this.mediaQuery.addEventListener?.("change", this.onViewport)
    this.refresh()
    this.render()
  }

  disconnect() {
    this.mediaQuery.removeEventListener?.("change", this.onViewport)
    if (this.videoUrl) URL.revokeObjectURL(this.videoUrl)
    if (this.reviewCoverUrl) URL.revokeObjectURL(this.reviewCoverUrl)
  }

  next(event) {
    event?.preventDefault()
    if (!this.validCurrentSection()) return
    this.step = Math.min(this.step + 1, this.sectionTargets.length - 1)
    this.render()
    this.focusSection()
  }

  back(event) {
    event?.preventDefault()
    this.step = Math.max(this.step - 1, 0)
    this.render()
    this.focusSection()
  }

  goTo(event) {
    event?.preventDefault()
    const nextStep = Number(event.currentTarget.dataset.step)
    if (!Number.isInteger(nextStep)) return
    if (nextStep > this.step && !this.validCurrentSection()) return
    this.step = Math.max(0, Math.min(nextStep, this.sectionTargets.length - 1))
    this.render()
    this.focusSection()
  }

  refresh() {
    const title = this.element.querySelector("[name=\"listing[title]\"]")?.value || ""
    const price = this.element.querySelector("[name=\"listing[price_cents]\"]")?.value || ""
    const condition = this.element.querySelector("[name=\"listing[condition]\"]")?.selectedOptions?.[0]?.textContent || ""
    const location = this.element.querySelector("[name=\"listing[location]\"]")?.value || ""
    const source = this.element.querySelector("[name=\"listing[source]\"]:checked")?.closest("label")?.innerText?.trim() || ""

    if (this.reviewCoverUrl) URL.revokeObjectURL(this.reviewCoverUrl)
    this.reviewCoverUrl = null
    const photo = Array.from(this.element.querySelector("[name='listing[photos][]']")?.files || [])
      .find(file => file.type.startsWith("image/"))
    if (this.hasReviewCoverTarget) {
      this.reviewCoverTarget.replaceChildren()
      if (photo) {
        this.reviewCoverUrl = URL.createObjectURL(photo)
        const image = document.createElement("img")
        image.src = this.reviewCoverUrl
        image.alt = ""
        image.className = "listing-review-cover-image"
        this.reviewCoverTarget.appendChild(image)
      } else {
        this.reviewCoverTarget.textContent = title.charAt(0).toUpperCase() || "?"
      }
    }

    if (this.hasReviewTitleTarget) this.reviewTitleTarget.textContent = title || this.text("untitled", "Untitled listing")
    if (this.hasReviewPriceTarget) this.reviewPriceTarget.textContent = price ? this.money(price) : this.text("priceUnset", "Price not set")
    if (this.hasReviewConditionTarget) this.reviewConditionTarget.textContent = condition || this.text("conditionUnset", "Condition not set")
    if (this.hasReviewLocationTarget) this.reviewLocationTarget.textContent = location || this.text("locationUnset", "Location not set")
    if (this.hasReviewSourceTarget) this.reviewSourceTarget.textContent = source || this.text("person", "From a person")

    const photoInput = this.element.querySelector("[name=\"listing[photos][]\"]")
    const imageCount = Array.from(photoInput?.files || []).filter(file => file.type.startsWith("image/")).length
    if (this.hasPhotoHintTarget) {
      const goods = this.element.querySelector("[name=\"listing[kind]\"]")?.value === "goods"
      this.photoHintTarget.hidden = !goods || imageCount >= 3
      if (goods && imageCount < 3) this.photoHintTarget.textContent = this.text("photoPrompt", "Most successful listings have 4–6 photos.")
    }
  }

  triggerVideo() {
    this.element.querySelector("[name=\"listing[video]\"]")?.click()
  }

  previewVideo(event) {
    const file = event.currentTarget.files?.[0]
    if (this.videoUrl) URL.revokeObjectURL(this.videoUrl)
    this.videoUrl = null
    if (!file || !file.type.startsWith("video/")) {
      if (this.hasVideoPreviewTarget) this.videoPreviewTarget.replaceChildren()
      return
    }

    this.videoUrl = URL.createObjectURL(file)
    const video = document.createElement("video")
    video.src = this.videoUrl
    video.controls = true
    video.preload = "metadata"
    video.className = "listing-video-preview"
    video.setAttribute("aria-label", file.name)
    this.videoPreviewTarget.replaceChildren(video)
  }

  useLocation(event) {
    event?.preventDefault()
    if (!navigator.geolocation) {
      this.locationStatusTarget.textContent = this.text("locationUnavailable", "Location is not available on this device.")
      return
    }

    this.locationStatusTarget.textContent = this.text("locating", "Getting your current location…")
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        const lat = this.element.querySelector("[name=\"listing[latitude]\"]")
        const lng = this.element.querySelector("[name=\"listing[longitude]\"]")
        if (lat) lat.value = coords.latitude.toFixed(6)
        if (lng) lng.value = coords.longitude.toFixed(6)
        this.locationStatusTarget.textContent = this.text("locationPinned", "Current coordinates added. Add the place name above.")
      },
      () => {
        this.locationStatusTarget.textContent = this.text("locationDenied", "Could not read your location. You can enter it manually.")
      },
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 }
    )
  }

  async saveDraft(event) {
    event?.preventDefault()
    const controller = this.application.getControllerForElementAndIdentifier(this.element, "draft-store")
    if (!controller) return
    await controller.save()
    this.draftStatusTarget.textContent = this.text("draftSaved", "Draft saved on this device.")
  }

  validCurrentSection() {
    if (!this.mediaQuery.matches) return true
    const section = this.sectionTargets[this.step]
    if (!section) return true

    const fields = Array.from(section.querySelectorAll("input, select, textarea"))
      .filter(field => !field.disabled && field.type !== "hidden" && field.type !== "file")
    for (const field of fields) {
      if (!field.checkValidity()) {
        field.reportValidity()
        return false
      }
    }
    return true
  }

  render() {
    const mobile = this.mediaQuery.matches
    this.sectionTargets.forEach((section, index) => {
      section.hidden = mobile && index !== this.step
      section.dataset.current = index === this.step ? "true" : "false"
    })
    this.stepLinkTargets.forEach((link, index) => {
      link.classList.toggle("is-active", index === this.step)
      if (index === this.step) link.setAttribute("aria-current", "step")
      else link.removeAttribute("aria-current")
    })
  }

  focusSection() {
    if (!this.mediaQuery.matches) return
    this.sectionTargets[this.step]?.querySelector("legend")?.focus?.()
  }

  money(ore) {
    const value = Number(ore)
    if (!Number.isFinite(value)) return ore
    return new Intl.NumberFormat(document.documentElement.lang || "en", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value / 100)
  }

  text(key, fallback) {
    const name = "listingForm" + key.charAt(0).toUpperCase() + key.slice(1)
    return this.element.dataset[name + "Value"] || fallback
  }
}
