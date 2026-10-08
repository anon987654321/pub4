import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values={throttleDelay:{type:Number,default:15}}
  initialize(){const scroll=this.scroll.bind(this);this.scroll=this.throttleDelayValue>0?this.throttle(scroll,this.throttleDelayValue):scroll}
  connect(){window.addEventListener("scroll",this.scroll,{passive:true});this.scroll()}
  disconnect(){window.removeEventListener("scroll",this.scroll)}
  scroll(){const height=document.documentElement.scrollHeight-document.documentElement.clientHeight;const width=height>0?(window.scrollY/height)*100:0;this.element.style.width=Math.max(0,Math.min(100,width))+"%"}
  throttle(callback,delay){let waiting=false;return(...args)=>{if(waiting)return;callback(...args);waiting=true;setTimeout(()=>{waiting=false},delay)}}
}
