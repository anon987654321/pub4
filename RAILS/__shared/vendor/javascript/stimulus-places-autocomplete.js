import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["address","city","streetNumber","route","postalCode","country","county","state","longitude","latitude"]
  static values={country:Array}
  initialize(){this.placeChanged=this.placeChanged.bind(this)}
  connect(){if(typeof google!=="undefined"&&google.maps?.places)this.initAutocomplete()}
  initAutocomplete(){this.autocomplete=new google.maps.places.Autocomplete(this.addressTarget,this.autocompleteOptions);this.autocomplete.addListener("place_changed",this.placeChanged)}
  placeChanged(){this.place=this.autocomplete.getPlace();const data={};(this.place.address_components||[]).forEach(c=>{data[c.types[0]]=c.long_name});if(this.hasStreetNumberTarget)this.streetNumberTarget.value=data.street_number||"";if(this.hasRouteTarget)this.routeTarget.value=data.route||"";if(this.hasCityTarget)this.cityTarget.value=data.locality||"";if(this.hasCountyTarget)this.countyTarget.value=data.administrative_area_level_2||"";if(this.hasStateTarget)this.stateTarget.value=data.administrative_area_level_1||"";if(this.hasCountryTarget)this.countryTarget.value=data.country||"";if(this.hasPostalCodeTarget)this.postalCodeTarget.value=data.postal_code||"";if(this.place.geometry?.location){if(this.hasLongitudeTarget)this.longitudeTarget.value=this.place.geometry.location.lng().toString();if(this.hasLatitudeTarget)this.latitudeTarget.value=this.place.geometry.location.lat().toString()}}
  get autocompleteOptions(){return{fields:["address_components","geometry"],componentRestrictions:{country:this.countryValue}}}
  preventSubmit(event){if(event.code==="Enter")event.preventDefault()}
}
