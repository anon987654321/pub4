// Controllers only brgen's own views and engines mount. Split out of
// stimulus_boot.js so amber and bsdports never import these modules.
// See stimulus_boot.js for controllers every app registers, and
// stimulus_boot_social.js for the ones brgen shares with amber.
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Dropdown from "@stimulus-components/dropdown"
import Sortable from "@stimulus-components/sortable"
import AnimatedNumber from "@stimulus-components/animated-number"
import BrgenShell from "pub4/brgen_shell"
import Dismiss from "pub4/dismiss"
import SearchPalette from "pub4/search_palette"
import ConversationLog from "pub4/conversation_log"
import OptimisticSend from "pub4/optimistic_send"
import Presence from "pub4/presence"
import LazyImage from "controllers/lazy_image_controller"

// @stimulus-components packages, matching stimulus_boot.js's own table
// convention — see its COMPONENT_REGISTRATIONS for why these stay separate
// from the plain application.register() calls below.
const COMPONENT_REGISTRATIONS = [
  ["checkbox-select-all", CheckboxSelectAll],
  ["dropdown", Dropdown],
  // shared/frontend/examples.html.erb offers a sortable snippet; see
  // SharedStimulusComponentsTest, which holds every offered snippet to a
  // live registration in one of the four boot files.
  ["sortable", Sortable],
  ["animated-number", AnimatedNumber],
]

export function bootBrgenStimulus(application) {
  application.register("brgen-shell", BrgenShell)
  application.register("dismiss", Dismiss)
  application.register("search-palette", SearchPalette)
  application.register("conversation-log", ConversationLog)
  application.register("optimistic-send", OptimisticSend)
  application.register("presence", Presence)
  application.register("lazy-image", LazyImage)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => application.register(name, component))
}
