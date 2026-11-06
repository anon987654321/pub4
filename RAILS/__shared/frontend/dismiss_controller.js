// Remove a transient element on demand — nearby alerts, inline notices.
//
// Exists because the one place that needed it used an inline
// onclick="this.closest('.nearby-alert').remove()". The CSP this family sends
// is `script-src 'self' https: 'nonce-…'`, which does not admit inline handlers,
// so that button worked only because the policy is still Report-Only. Enforcing
// it would have silently stopped the close button from closing.
//
// @stimulus-components/notification was the alternative, and it is the wrong
// shape here: it auto-hides on a timer, and a nearby alert persists until the
// reader dismisses it.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    // Ancestor to remove. Defaults to the controller's own element, which is
    // the right answer when the controller sits on the thing being dismissed.
    target: String
  }

  remove(event) {
    event?.preventDefault()
    const node = this.hasTargetValue ? this.element.closest(this.targetValue) : this.element
    node?.remove()
  }
}
