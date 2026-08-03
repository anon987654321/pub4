import { Controller } from "@hotwired/stimulus"
import { enqueueSync } from "pwa/offline_store"

export default class extends Controller {
  static values = { likeUrl: String, dislikeUrl: String, listenUrl: String, mode: String }

  connect() {
    this.stack = this.element.querySelector("#swipe-stack")
    this.gallery = this.element.querySelector(".media-gallery")
    this.mode = this.hasModeValue ? this.modeValue : this._defaultMode()
    this.cards = this.stack ? Array.from(this.stack.querySelectorAll(".swipe-card")).reverse() : []
    this.currentCard = this.cards[this.cards.length - 1]
    this.carouselItems = this.gallery ? Array.from(this.gallery.querySelectorAll(".media-gallery__item")) : []
    this.startX = 0
    this.currentX = 0
    this.isDragging = false
    this.threshold = 80
    this.maxRotate = 18
  }

  disconnect() {
    this.isDragging = false
  }

  _defaultMode() {
    if (this.stack && this.cards?.length) return "dating"
    if (this.hasListenUrlValue) return "queue"
    if (this.gallery) return "carousel"
    return "dating"
  }

  _interactiveTarget(e) {
    const interactive = e.target.closest("button, input, textarea, select, option, [data-swipe-ignore='true']")
    if (interactive) return interactive
    if (this.mode !== "carousel" && e.target.closest("a")) return e.target.closest("a")
    return null
  }

  pointerDown(e) {
    if (this._interactiveTarget(e)) return
    if (this.mode === "dating" && !this.currentCard) return
    if (this.mode === "carousel" && !this.gallery) return
    if (this.mode === "queue" && !this.hasListenUrlValue) return
    this.isDragging = true
    this.startX = e.clientX || (e.touches && e.touches[0].clientX) || 0
    if (this.currentCard) this.currentCard.classList.add("dragging")
    if (this.gallery) this.gallery.classList.add("dragging")
    e.preventDefault()
  }

  pointerMove(e) {
    if (!this.isDragging) return
    const clientX = e.clientX || (e.touches && e.touches[0].clientX) || 0
    this.currentX = clientX - this.startX

    if (this.mode === "carousel" && this.gallery) {
      this.gallery.scrollLeft -= this.currentX * 0.35
      this.startX = clientX
      return
    }

    if (!this.currentCard) return
    const rotate = (this.currentX / this.threshold) * this.maxRotate
    const scale = 1 - Math.abs(this.currentX) / 1200
    this.currentCard.style.transform = `translateX(${this.currentX}px) rotate(${rotate}deg) scale(${Math.max(0.96, scale)})`

    // Visual feedback
    if (this.currentX > 40) {
      this.currentCard.classList.add("liked")
      this.currentCard.classList.remove("passed")
    } else if (this.currentX < -40) {
      this.currentCard.classList.add("passed")
      this.currentCard.classList.remove("liked")
    } else {
      this.currentCard.classList.remove("liked", "passed")
    }
  }

  async pointerUp(e) {
    if (!this.isDragging) return
    this.isDragging = false
    if (this.currentCard) this.currentCard.classList.remove("dragging")
    if (this.gallery) this.gallery.classList.remove("dragging")

    const delta = this.currentX

    if (this.mode === "carousel" && this.gallery) {
      if (Math.abs(delta) > this.threshold) {
        const direction = delta > 0 ? -1 : 1
        const item = this.carouselItems.find(el => el.getBoundingClientRect().width > 0) || this.gallery.querySelector(".media-gallery__item")
        const width = item ? item.getBoundingClientRect().width + 12 : this.gallery.clientWidth * 0.75
        this.gallery.scrollBy({ left: direction * width, behavior: "smooth" })
      }
      this.currentX = 0
      return
    }

    if (this.mode === "queue" && this.hasListenUrlValue) {
      if (delta > this.threshold) {
        await this._queueTrack()
      }
      this.currentX = 0
      return
    }

    if (Math.abs(delta) > this.threshold) {
      const isLike = delta > 0
      const url = isLike ? this.likeUrlValue : this.dislikeUrlValue
      const userId = this.currentCard.dataset.userId
      const card = this.currentCard

      // A short buzz on commit — a like feels different from a pass.
      if (navigator.vibrate) navigator.vibrate(isLike ? [12, 30, 12] : 8)

      // Commit animation offscreen
      const direction = isLike ? 1 : -1
      card.style.transition = "transform 220ms cubic-bezier(0.32,0.72,0,1), opacity 180ms"
      card.style.transform = `translateX(${direction * 520}px) rotate(${direction * 22}deg)`
      card.style.opacity = "0.1"

      // Fire backend (AJAX, no full redirect thanks to controller)
      try {
        const formData = new FormData()
        formData.append("user_id", userId)
        const resp = await fetch(url, {
          method: "POST",
          body: formData,
          headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content, "Accept": "text/vnd.turbo-stream.html, text/html" }
        })
        if (resp.ok) {
          // Remove immediately
          setTimeout(() => {
            if (card?.parentNode) card.parentNode.removeChild(card)
            this.cards = this.cards.filter(c => c !== card)
            this.currentCard = this.cards[this.cards.length - 1]
            if (this.currentCard) {
              this.currentCard.style.transition = ""
              this.currentCard.style.transform = ""
              this.currentCard.style.opacity = ""
            }
            // A real match is decided on the server: Dating::Like#check_mutual_match
            // creates a Dating::Match on a reciprocated like, and Match#announce_match
            // broadcasts the overlay to both users over the match stream this page
            // already subscribes to. No client-side guessing — a match appears only
            // when it is actually mutual.
          }, 180)
        }
      } catch (err) {
        console.error("swipe commit failed", err)
        await enqueueSync({ url, method: "POST", body: { user_id: userId } })
        setTimeout(() => {
          if (card?.parentNode) card.parentNode.removeChild(card)
          this.cards = this.cards.filter(c => c !== card)
          this.currentCard = this.cards[this.cards.length - 1]
          if (this.currentCard) {
            this.currentCard.style.transition = ""
            this.currentCard.style.transform = ""
            this.currentCard.style.opacity = ""
          }
        }, 180)
      }
    } else {
      // Spring back
      this.currentCard.style.transition = "transform 380ms cubic-bezier(0.32,0.72,0,1)"
      this.currentCard.style.transform = ""
      this.currentCard.classList.remove("liked", "passed")

      setTimeout(() => {
        if (this.currentCard) this.currentCard.style.transition = ""
      }, 420)
    }

    this.currentX = 0
  }

  // Button fallbacks
  like() {
    if (!this.currentCard) return
    this.currentX = this.threshold + 10
    this._commitLike()
  }

  pass() {
    if (!this.currentCard) return
    this.currentX = -(this.threshold + 10)
    this._commitLike()
  }

  async _commitLike() {
    const isLike = this.currentX > 0
    const url = isLike ? this.likeUrlValue : this.dislikeUrlValue
    const userId = this.currentCard.dataset.userId

    this.currentCard.style.transition = "transform 220ms cubic-bezier(0.32,0.72,0,1)"
    const dir = isLike ? 1 : -1
    this.currentCard.style.transform = `translateX(${dir * 480}px) rotate(${dir * 20}deg)`

    try {
      const formData = new FormData()
      formData.append("user_id", userId)
      await fetch(url, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "text/vnd.turbo-stream.html, text/html"
        }
      })
    } catch (_) {
      await enqueueSync({ url, method: "POST", body: { user_id: userId } })
    }

    setTimeout(() => {
      if (this.currentCard) {
        this.currentCard.remove()
        this.cards.pop()
        this.currentCard = this.cards[this.cards.length - 1]
        if (this.mode === "dating") this._hydrateNextCard()
      }
    }, 200)
  }

  async _queueTrack() {
    if (!this.hasListenUrlValue) return
    const row = this.element.closest("[data-track-id]") || this.element
    if (row) {
      row.classList.add("liked")
      row.style.transition = "transform 220ms cubic-bezier(0.32,0.72,0,1), opacity 180ms"
      row.style.transform = "translateX(160px)"
      row.style.opacity = "0.1"
    }

    try {
      const response = await fetch(this.listenUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })
      if (!response.ok) throw new Error(`queue failed: ${response.status}`)
    } catch (err) {
      console.error("playlist queue swipe failed", err)
      if (row) {
        row.classList.remove("liked")
        row.style.transition = "transform 220ms cubic-bezier(0.32,0.72,0,1), opacity 180ms"
        row.style.transform = ""
        row.style.opacity = ""
      }
      return
    }

    setTimeout(() => {
      if (row) {
        row.classList.add("queued")
        row.style.opacity = ""
        row.style.transform = ""
      }
    }, 180)
  }

  _hydrateNextCard() {
    const frame = document.getElementById("dating-next")
    if (!frame) return
    const nextCard = frame.querySelector(".swipe-card")
    if (!nextCard) {
      const src = frame.getAttribute("src")
      if (src) frame.setAttribute("src", `${src.split("?")[0]}?reload=${Date.now()}`)
      return
    }

    nextCard.style.position = "absolute"
    nextCard.style.inset = "0"
    nextCard.style.willChange = "transform,opacity"
    this.stack.prepend(nextCard)
    this.cards = Array.from(this.stack.querySelectorAll(".swipe-card")).reverse()
    this.currentCard = this.cards[this.cards.length - 1]

    const src = frame.getAttribute("src")
    if (src) frame.setAttribute("src", `${src.split("?")[0]}?reload=${Date.now()}`)
  }
}
