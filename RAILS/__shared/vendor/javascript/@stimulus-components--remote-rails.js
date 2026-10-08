import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  replace(event){event.preventDefault();event.stopPropagation();const xhr=(event.detail||[])[2];if(xhr?.response)this.element.outerHTML=xhr.response}
  append(event){event.preventDefault();event.stopPropagation();const xhr=(event.detail||[])[2];if(xhr?.response)this.element.insertAdjacentHTML("afterend",xhr.response)}
  prepend(event){event.preventDefault();event.stopPropagation();const xhr=(event.detail||[])[2];if(xhr?.response)this.element.insertAdjacentHTML("beforebegin",xhr.response)}
}
