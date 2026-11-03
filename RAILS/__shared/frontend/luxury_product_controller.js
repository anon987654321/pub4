// Luxury product interactions (Aesop/Toteme/Nécessaire inspired)
// Subtle hover zoom on images, quick action feedback, calm micro-interactions
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["photo"]

  // Gentle zoom on image hover (no heavy animation)
  photoTargetConnected(element) {
    element.addEventListener("mouseenter", () => {
      element.style.transform = "scale(1.015)"
      element.style.transition = "transform 220ms cubic-bezier(0.25, 0.1, 0.25, 1)"
    })
    element.addEventListener("mouseleave", () => {
      element.style.transform = "scale(1)"
    })
  }

  // Optional: quick "wear" feedback with temporary class
  wear(event) {
    const button = event.currentTarget
    const originalText = button.textContent
    button.textContent = "Added ✓"
    button.disabled = true

    setTimeout(() => {
      if (button) {
        button.textContent = originalText
        button.disabled = false
      }
    }, 1400)
  }
}
