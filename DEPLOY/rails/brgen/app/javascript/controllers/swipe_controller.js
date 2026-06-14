import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { likeUrl: String, dislikeUrl: String }

  connect() {
    this.stack = this.element.querySelector("#swipe-stack")
    this.cards = Array.from(this.stack.querySelectorAll(".swipe-card")).reverse()
    this.currentCard = this.cards[this.cards.length - 1]
    this.startX = 0
    this.currentX = 0
    this.isDragging = false
    this.threshold = 80
    this.maxRotate = 18
  }

  pointerDown(e) {
    if (!this.currentCard) return
    this.isDragging = true
    this.startX = e.clientX || (e.touches && e.touches[0].clientX) || 0
    this.currentCard.classList.add("dragging")
    e.preventDefault()
  }

  pointerMove(e) {
    if (!this.isDragging || !this.currentCard) return
    const clientX = e.clientX || (e.touches && e.touches[0].clientX) || 0
    this.currentX = clientX - this.startX

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
    if (!this.isDragging || !this.currentCard) return
    this.isDragging = false
    this.currentCard.classList.remove("dragging")

    const delta = this.currentX

    if (Math.abs(delta) > this.threshold) {
      const isLike = delta > 0
      const url = isLike ? this.likeUrlValue : this.dislikeUrlValue
      const userId = this.currentCard.dataset.userId
      const card = this.currentCard

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
            if (card && card.parentNode) card.parentNode.removeChild(card)
            this.cards = this.cards.filter(c => c !== card)
            this.currentCard = this.cards[this.cards.length - 1]
            if (this.currentCard) {
              this.currentCard.style.transition = ""
              this.currentCard.style.transform = ""
              this.currentCard.style.opacity = ""
            }
            // Optional: flash success or update matches count
            if (isLike && Math.random() > 0.7) { // simulate possible mutual
              alert("It\'s a match! Check your matches.")
              window.location.href = "/dating/matches"  // or Turbo visit
            }
          }, 180)
        }
      } catch (err) {
        console.error("swipe commit failed", err)
        // revert card on error
        card.style.transition = "transform 300ms"
        card.style.transform = ""
        card.style.opacity = ""
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
      await fetch(url, { method: "POST", body: formData, headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content } })
    } catch (_) {}

    setTimeout(() => {
      if (this.currentCard) {
        this.currentCard.remove()
        this.cards.pop()
        this.currentCard = this.cards[this.cards.length - 1]
      }
    }, 200)
  }
}
