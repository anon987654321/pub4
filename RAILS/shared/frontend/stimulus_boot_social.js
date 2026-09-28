// Controllers mounted only by brgen and amber's views — not bsdports.
// Split out of stimulus_boot.js so bsdports never imports these modules.
// See stimulus_boot.js for controllers every app registers.
import Lightbox from "@stimulus-components/lightbox"
import MediaExclusive from "pub4/media_exclusive"
import BrowserFingerprint from "pub4/browser_fingerprint"
import DirectUpload from "pub4/direct_upload"
import ScrollChrome from "pub4/scroll_chrome"
import Autosave from "pub4/autosave"
import DraftStore from "pub4/draft_store"
import MediaPicker from "pub4/media_picker"
import FeedCompose from "pub4/feed_compose"
import VisualSurface from "pub4/visual_surface"

// @stimulus-components packages, matching stimulus_boot.js's own table
// convention — see its COMPONENT_REGISTRATIONS for why these stay separate
// from the plain application.register() calls below.
const COMPONENT_REGISTRATIONS = [
  // shared/frontend/examples.html.erb offers a lightbox snippet; see
  // SharedStimulusComponentsTest, which holds every offered snippet to a
  // live registration in one of the four boot files.
  ["lightbox", Lightbox],
]

export function bootSocialStimulus(application) {
  application.register("media-exclusive", MediaExclusive)
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("scroll-chrome", ScrollChrome)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)
  application.register("visual-field", VisualSurface)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => application.register(name, component))
}
