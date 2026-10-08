import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["child","overlay"]
  initialize(){this.move=this.move.bind(this)}
  connect(){if(!this.hasChildTarget||!this.hasOverlayTarget)return;this.overlayTarget.append(this.childTarget.cloneNode(true));document.body.addEventListener("pointermove",this.move)}
  disconnect(){document.body.removeEventListener("pointermove",this.move)}
  move(event){const x=event.pageX-this.element.offsetLeft,y=event.pageY-this.element.offsetTop;this.element.style.setProperty("--glow-opacity","1");this.element.style.setProperty("--glow-x",x+"px");this.element.style.setProperty("--glow-y",y+"px")}
}
