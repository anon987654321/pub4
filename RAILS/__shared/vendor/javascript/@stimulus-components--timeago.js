import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values={datetime:String,refreshInterval:Number,includeSeconds:Boolean,addSuffix:Boolean}
  connect(){this.isValid=true;this.load();if(this.hasRefreshIntervalValue&&this.isValid)this.startRefreshing()}
  disconnect(){this.stopRefreshing()}
  load(){const datetime=this.datetimeValue,date=Date.parse(datetime);if(Number.isNaN(date)){this.isValid=false;this.element.dateTime=datetime;this.element.textContent=datetime;return}this.isValid=true;this.element.dateTime=datetime;this.element.textContent=this.format(date)}
  format(date){const diff=date-Date.now(),abs=Math.abs(diff);const units=this.includeSecondsValue?[["year",31536000000],["month",2592000000],["week",604800000],["day",86400000],["hour",3600000],["minute",60000],["second",1000]]:[["year",31536000000],["month",2592000000],["week",604800000],["day",86400000],["hour",3600000],["minute",60000]];const unit=units.find(([,size])=>abs>=size)||["second",1000],value=Math.max(1,Math.round(diff/unit[1]));if(!this.addSuffixValue)return Math.abs(value)+" "+unit[0]+(Math.abs(value)===1?"":"s");return new Intl.RelativeTimeFormat(document.documentElement.lang||"en",{numeric:"auto"}).format(value,unit[0])}
  startRefreshing(){this.refreshTimer=setInterval(()=>this.load(),this.refreshIntervalValue)}
  stopRefreshing(){if(this.refreshTimer)clearInterval(this.refreshTimer)}
}
