import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values={resizeDebounceDelay:{type:Number,default:100}}
  initialize(){this.autogrow=this.autogrow.bind(this)}
  connect(){this.element.style.overflow="hidden";this.onResize=this.resizeDebounceDelayValue>0?this.debounce(this.autogrow,this.resizeDebounceDelayValue):this.autogrow;this.autogrow();this.element.addEventListener("input",this.autogrow);window.addEventListener("resize",this.onResize)}
  disconnect(){this.element.removeEventListener("input",this.autogrow);window.removeEventListener("resize",this.onResize)}
  autogrow(){this.element.style.height="auto";this.element.style.height=this.element.scrollHeight+"px"}
  debounce(callback,delay){let timeout;return(...args)=>{clearTimeout(timeout);timeout=setTimeout(()=>callback(...args),delay)}}
}
