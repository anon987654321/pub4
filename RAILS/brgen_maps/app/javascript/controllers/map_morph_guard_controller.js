import { Controller } from "@hotwired/stimulus"

// The server renders #map as an empty div; the canvas, the navigation controls
// and the markers exist only in the browser. A Turbo morph rebuilds the page
// toward server HTML, so morphing the map section would tear the running map's
// WebGL context out from under it. This controller keeps the section out of
// the morph while it is connected, the way tiptap_editor_controller.js keeps a
// mounted editor out of it. The guard refuses only the morph, not a Drive
// load, so a revisit still reboots the map from fresh server data.
export default class extends Controller {
  connect() {
    this.keepThroughMorph = this.keepThroughMorph.bind(this)
    this.element.addEventListener("turbo:before-morph-element", this.keepThroughMorph)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-element", this.keepThroughMorph)
  }

  keepThroughMorph(event) {
    if (event.target === this.element) event.preventDefault()
  }
}
