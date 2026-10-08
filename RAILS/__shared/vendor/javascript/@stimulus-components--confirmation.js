import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["input","item"]
  check(){const disabled=this.inputTargets.some(input=>input.type==="checkbox"?!input.checked:input.dataset.confirmationContent!==input.value);this.itemTargets.forEach(target=>{target.disabled=disabled})}
  inputTargetConnected(){this.check()}
  inputTargetDisconnected(){this.check()}
}
