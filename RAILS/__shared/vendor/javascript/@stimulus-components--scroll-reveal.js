import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["item"]
  static values={class:String,threshold:Number,rootMargin:String}
  initialize(){this.intersectionObserverCallback=this.intersectionObserverCallback.bind(this)}
  connect(){this.class=this.classValue||this.defaultOptions.class||"in";this.threshold=this.thresholdValue||this.defaultOptions.threshold||0.1;this.rootMargin=this.rootMarginValue||this.defaultOptions.rootMargin||"0px";this.observer=new IntersectionObserver(this.intersectionObserverCallback,{threshold:this.threshold,rootMargin:this.rootMargin});this.itemTargets.forEach(item=>this.observer.observe(item))}
  disconnect(){this.observer?.disconnect()}
  intersectionObserverCallback(entries,observer){entries.forEach(entry=>{if(entry.intersectionRatio>this.threshold){const target=entry.target;target.classList.add(...this.class.split(" "));if(target.dataset.delay)target.style.transitionDelay=target.dataset.delay;observer.unobserve(target)}})}
  get defaultOptions(){return{}}
}
