// Controllers only amber's own views mount. Split out of stimulus_boot.js
// so brgen and bsdports never import these modules. See stimulus_boot.js
// for controllers every app registers, and stimulus_boot_social.js for
// the ones amber shares with brgen.
import RailsNestedForm from "@stimulus-components/rails-nested-form"
import OutboundClick from "pub4/outbound_click"
import LuxuryProduct from "pub4/luxury_product"
import EdgeSwiper from "pub4/edge_swiper"

// @stimulus-components packages, matching stimulus_boot.js's own table
// convention — see its COMPONENT_REGISTRATIONS for why these stay separate
// from the plain application.register() calls below.
const COMPONENT_REGISTRATIONS = [
  ["nested-form", RailsNestedForm],
]

export function bootAmberStimulus(application) {
  application.register("outbound-click", OutboundClick)
  application.register("luxury-product", LuxuryProduct)
  application.register("edge-swiper", EdgeSwiper)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => application.register(name, component))
}
