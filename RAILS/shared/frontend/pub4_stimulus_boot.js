// Registers @stimulus-components baseline + StimulusReflex (+ optional Futurism).
import AutoSubmit from "@stimulus-components/auto-submit"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Clipboard from "@stimulus-components/clipboard"
import ContentLoader from "@stimulus-components/content-loader"
import Dialog from "@stimulus-components/dialog"
import Dropdown from "@stimulus-components/dropdown"
import Hotkey from "@stimulus-components/hotkey"
import Lightbox from "@stimulus-components/lightbox"
import Notification from "@stimulus-components/notification"
import Popover from "@stimulus-components/popover"
import ReadMore from "@stimulus-components/read-more"
import Reveal from "@stimulus-components/reveal"
import ScrollTo from "@stimulus-components/scroll-to"
import Sortable from "@stimulus-components/sortable"
import Sound from "@stimulus-components/sound"
import SpeechRecognition from "@stimulus-components/speech-recognition"
import TextareaAutogrow from "@stimulus-components/textarea-autogrow"
import Timeago from "@stimulus-components/timeago"
import AnimatedNumber from "@stimulus-components/animated-number"
import PasswordVisibility from "@stimulus-components/password-visibility"
import RailsNestedForm from "@stimulus-components/rails-nested-form"
import Carousel from "@stimulus-components/carousel"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"
import LiveSearch from "pub4/live_search"
import OfflinePage from "pub4/offline_page"
import InstallPrompt from "pub4/install_prompt"
import ThemeToggle from "pub4/theme_toggle"
import InfiniteScroll from "pub4/infinite_scroll"
import BrowserFingerprint from "pub4/browser_fingerprint"
import DirectUpload from "pub4/direct_upload"
import CharacterCounter from "pub4/character_counter"
import LuxuryProduct from "pub4/luxury_product"
import ScrollReveal from "pub4/scroll_reveal"
import XAction from "pub4/x_action"
import Autosave from "pub4/autosave"
import DraftStore from "pub4/draft_store"
import MediaPicker from "pub4/media_picker"
import FeedCompose from "pub4/feed_compose"

const COMPONENT_REGISTRATIONS = [
  ["auto-submit", AutoSubmit],
  ["character-counter", CharacterCounter],
  ["checkbox-select-all", CheckboxSelectAll],
  ["clipboard", Clipboard],
  ["content-loader", ContentLoader],
  ["dialog", Dialog],
  ["dropdown", Dropdown],
  ["hotkey", Hotkey],
  ["lightbox", Lightbox],
  ["notification", Notification],
  ["toast", Notification],
  ["popover", Popover],
  ["read-more", ReadMore],
  ["reveal", Reveal],
  ["scroll-to", ScrollTo],
  ["sortable", Sortable],
  ["sound", Sound],
  ["speech-recognition", SpeechRecognition],
  ["textarea-autogrow", TextareaAutogrow],
  ["timeago", Timeago],
  ["animated-number", AnimatedNumber],
  ["password-visibility", PasswordVisibility],
  ["nested-form", RailsNestedForm],
  ["rails-nested-form", RailsNestedForm],
  ["carousel", Carousel],
]

export function bootPub4Stimulus(application, { futurism = true } = {}) {
  application.register("live-search", LiveSearch)
  application.register("offline-page", OfflinePage)
  application.register("install-prompt", InstallPrompt)
  application.register("theme-toggle", ThemeToggle)
  application.register("infinite-scroll", InfiniteScroll)
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("luxury-product", LuxuryProduct)
  application.register("scroll-reveal", ScrollReveal)
  application.register("x-action", XAction)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => {
    application.register(name, component)
  })

  StimulusReflex.initialize(application, {
    applicationController: ApplicationController,
    isolate: true
  })

  if (futurism) {
    import("@stimulus_reflex/futurism").then(({ default: Futurism }) => {
      application.register("futurism", Futurism)
    })
  }
}
