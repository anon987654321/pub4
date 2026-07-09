import Lightbox from "@stimulus-components/lightbox"

export default class extends Lightbox {
  get defaultOptions() {
    return {
      licenseKey: document.head.querySelector("meta[name=lg-license]")?.content || "0000-0000-000-0000",
      speed: 400,
      download: true,
      counter: true,
      print: true,  // printout button
      mobileSettings: { controls: true, showCloseIcon: true, download: true }
    }
  }
}
