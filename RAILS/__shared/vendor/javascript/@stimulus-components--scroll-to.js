import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values={offset:Number,behavior:String}
  initialize(){this.scroll=this.scroll.bind(this)}
  connect(){this.element.addEventListener("click",this.scroll)}
  disconnect(){this.element.removeEventListener("click",this.scroll)}
  scroll(event){event.preventDefault();const id=this.element.hash.replace(/^#/,""),target=document.getElementById(id);if(!target)return;const position=target.getBoundingClientRect().top+window.scrollY;window.scrollTo({top:position-this.offset,behavior:this.behavior})}
  get offset(){return this.hasOffsetValue?this.offsetValue:10}
  get behavior(){return this.behaviorValue||"smooth"}
}
