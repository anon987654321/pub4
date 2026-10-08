import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["canvas"]
  static values={type:{type:String,default:"line"},data:Object,options:Object}
  connect(){this.canvas=this.hasCanvasTarget?this.canvasTarget:this.element;this.render()}
  disconnect(){const c=this.canvas?.getContext?.("2d");c?.clearRect(0,0,this.canvas.width,this.canvas.height)}
  render(){const c=this.canvas?.getContext?.("2d"),d=this.dataValue||{};if(!c)return;const v=Array.isArray(d.datasets)?d.datasets.flatMap(x=>Array.isArray(x.data)?x.data:[]).map(Number).filter(Number.isFinite):[];if(!v.length){this.canvas.dataset.chartjsEmpty="true";return}const w=this.canvas.clientWidth||this.canvas.width||320,h=this.canvas.clientHeight||this.canvas.height||180,s=window.devicePixelRatio||1;this.canvas.width=Math.max(1,Math.round(w*s));this.canvas.height=Math.max(1,Math.round(h*s));c.scale(s,s);const max=Math.max(...v),min=Math.min(...v),range=max-min||1,p=12;c.clearRect(0,0,w,h);c.beginPath();v.forEach((n,i)=>{const x=p+(i/Math.max(1,v.length-1))*(w-p*2),y=h-p-((n-min)/range)*(h-p*2);i?c.lineTo(x,y):c.moveTo(x,y)});c.stroke();this.canvas.dataset.chartjsReady="true"}
}
