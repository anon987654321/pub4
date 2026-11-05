// Registers the controllers every app uses, plus @stimulus-components
// baseline entries and StimulusReflex.
import AutoSubmit from "@stimulus-components/auto-submit"
import Clipboard from "@stimulus-components/clipboard"
import Notification from "@stimulus-components/notification"
import ReadMore from "@stimulus-components/read-more"
import Reveal from "@stimulus-components/reveal"
import PasswordVisibility from "@stimulus-components/password-visibility"
import Popover from "@stimulus-components/popover"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"
import LiveSearch from "pub4/live_search"
import SearchFocus from "pub4/search_focus"
import OfflinePage from "pub4/offline_page"
import { noteSession } from "pub4/onboarding"
import CookieConsent from "pub4/cookie_consent_controller"
import WelcomeOnboarding from "pub4/welcome_onboarding"
import LinkConverter from "pub4/link_converter"
import ThemeToggle from "pub4/theme_toggle"
import InfiniteScroll from "pub4/infinite_scroll"
import CharacterCounter from "pub4/character_counter"
import ParallaxTilt from "pub4/parallax_tilt"
import ScrollReveal from "pub4/scroll_reveal"
import NavAutohide from "pub4/nav_autohide"
import ActionController from "pub4/action"
import TiptapEditor from "pub4/tiptap_editor"
import CommentThread from "pub4/comment_thread"
import FeedHotkey from "pub4/feed_hotkey"
import NearbyChat from "pub4/nearby_chat"
import OfflineFeed from "pub4/offline_feed"
import PwaStandalone from "pub4/pwa_standalone"
import NetworkAware from "pub4/network_aware"
import ViewportAware from "pub4/viewport_aware"
import Haptics from "pub4/haptics"
import Geolocation from "pub4/geolocation"
import RailsNestedForm from "@stimulus-components/rails-nested-form"
import Lightbox from "@stimulus-components/lightbox"
import AnimatedNumber from "@stimulus-components/animated-number"
import Sortable from "@stimulus-components/sortable"
import Dropdown from "@stimulus-components/dropdown"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Timeago from "@stimulus-components/timeago"
import TextareaAutogrow from "@stimulus-components/textarea-autogrow"
import SpeechRecognition from "@stimulus-components/speech-recognition"
import Sound from "@stimulus-components/sound"
import ScrollTo from "@stimulus-components/scroll-to"
import ScrollProgress from "@stimulus-components/scroll-progress"
import RemoteRails from "@stimulus-components/remote-rails"
import Prefetch from "@stimulus-components/prefetch"
import PlacesAutocomplete from "stimulus-places-autocomplete"
import Hotkey from "@stimulus-components/hotkey"
import Dialog from "@stimulus-components/dialog"
import ContentLoader from "@stimulus-components/content-loader"
import Confirmation from "@stimulus-components/confirmation"
import ColorPicker from "@stimulus-components/color-picker"
import Chartjs from "@stimulus-components/chartjs"
import Carousel from "@stimulus-components/carousel"
import BottomSheet from "pub4/bottom_sheet"

// A counter counting up from its start is motion. Under prefers-reduced-motion
// it keeps the number the server rendered and never runs.
class CalmAnimatedNumber extends AnimatedNumber {
  connect() {
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return
    super.connect()
  }
}

const COMPONENT_REGISTRATIONS = [
  [ "animated-number", CalmAnimatedNumber ],
  [ "auto-submit", AutoSubmit ],
  [ "carousel", Carousel ],
  [ "chartjs", Chartjs ],
  [ "character-counter", CharacterCounter ],
  [ "checkbox-select-all", CheckboxSelectAll ],
  [ "clipboard", Clipboard ],
  [ "color-picker", ColorPicker ],
  [ "confirmation", Confirmation ],
  [ "content-loader", ContentLoader ],
  [ "dialog", Dialog ],
  [ "dropdown", Dropdown ],
  [ "hotkey", Hotkey ],
  [ "lightbox", Lightbox ],
  [ "notification", Notification ],
  [ "toast", Notification ],
  [ "password-visibility", PasswordVisibility ],
  [ "places-autocomplete", PlacesAutocomplete ],
  [ "popover", Popover ],
  [ "prefetch", Prefetch ],
  [ "nested-form", RailsNestedForm ],
  [ "read-more", ReadMore ],
  [ "remote-rails", RemoteRails ],
  [ "reveal", Reveal ],
  [ "scroll-progress", ScrollProgress ],
  [ "scroll-reveal", ScrollReveal ],
  [ "scroll-to", ScrollTo ],
  [ "sortable", Sortable ],
  [ "sound", Sound ],
  [ "speech-recognition", SpeechRecognition ],
  [ "textarea-autogrow", TextareaAutogrow ],
  [ "timeago", Timeago ],
]

export function bootPub4Stimulus(application) {
  noteSession()

  application.register("live-search", LiveSearch)
  application.register("search-focus", SearchFocus)
  application.register("offline-page", OfflinePage)
  application.register("cookie-consent", CookieConsent)
  application.register("welcome-onboarding", WelcomeOnboarding)
  application.register("link-converter", LinkConverter)
  application.register("theme-toggle", ThemeToggle)
  application.register("infinite-scroll", InfiniteScroll)
  application.register("nav-autohide", NavAutohide)
  application.register("action", ActionController)
  application.register("tiptap-editor", TiptapEditor)
  application.register("comment-thread", CommentThread)
  application.register("feed-hotkey", FeedHotkey)
  application.register("nearby-chat", NearbyChat)
  application.register("offline-feed", OfflineFeed)
  application.register("pwa-standalone", PwaStandalone)
  application.register("network-aware", NetworkAware)
  application.register("viewport-aware", ViewportAware)
  application.register("haptics", Haptics)
  application.register("geolocation", Geolocation)
  application.register("bottom-sheet", BottomSheet)
  application.register("parallax-tilt", ParallaxTilt)

  COMPONENT_REGISTRATIONS.forEach(([ name, component ]) => {
    if (component) application.register(name, component)
  })

  // stimulus_reflex 3.5.5's rejected() callback reads `Debug.enabled`, a name
  // its bundler renamed to Debug$1 everywhere else, so a refused subscription
  // threw "Debug is not defined". brgen refuses the reflex channel to every
  // connection with nobody behind it (ApplicationCable::Channel), so it threw
  // for each signed-out visitor. The stray read gets the value it meant:
  // debug logging off.
  if (!("Debug" in globalThis)) globalThis.Debug = Object.freeze({ enabled: false })
  StimulusReflex.initialize(application, {
    applicationController: ApplicationController,
    isolate: true
  })
}
