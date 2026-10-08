import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  initialize(){this.load=this.load.bind(this);this.prefetch=this.prefetch.bind(this)}
  connect(){if(this.hasPrefetch)this.load()}
  disconnect(){this.stopObserving()}
  load(){this.observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(!entry.isIntersecting)return;this.prefetch();this.stopObserving()}));this.observer.observe(this.element)}
  stopObserving(){this.observer?.disconnect();this.observer=undefined}
  prefetch(){const c=navigator.connection;if(c?.saveData||(c?.effectiveType&&c.effectiveType!=="4g"))return;const link=document.createElement("link");link.rel="prefetch";link.href=this.element.href;link.as="document";document.head.appendChild(link)}
  get hasPrefetch(){const link=document.createElement("link");return!!link.relList?.supports?.("prefetch")}
}
