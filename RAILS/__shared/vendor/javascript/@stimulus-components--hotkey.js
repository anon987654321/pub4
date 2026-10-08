import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  click(event){if(this.isClickable&&!this.shouldIgnore(event)){event.preventDefault();this.element.click()}}
  focus(event){if(this.isClickable&&!this.shouldIgnore(event)){event.preventDefault();this.element.focus()}}
  shouldIgnore(event){const target=event.target;return event.defaultPrevented||!!target?.closest("input, textarea, lexxy-editor")}
  get isClickable(){return getComputedStyle(this.element).pointerEvents!=="none"}
}
