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
import InstallPrompt from "pub4/install_prompt"
import { noteSession } from "pub4/onboarding"
import CookieConsent from "pub4/cookie_consent_controller"
import WelcomeOnboarding from "pub4/welcome_onboarding"
import NewsletterCapture from "pub4/newsletter_capture"
import NewsletterCapture from "pub4/newsletter_capture"
import LinkConverter from "pub4/link_converter"
import ThemeToggle from "pub4/theme_toggle"
import InfiniteScroll from "pub4/infinite_scroll"
import CharacterCounter from "pub4/character_counter"
import ParallaxTilt from "pub4/parallax_tilt"
import ScrollReveal from "pub4/scroll_reveal"
import NavAutohide from "pub4/nav_autohide"
import ActionController from "pub4/action"
import TiptapEditor from "pub4/tiptap_editor"
import FeedHotkey from "pub4/feed_hotkey"
import NearbyChat from "pub4/nearby_chat"
import OfflineFeed from "pub4/offline_feed"
import PwaStandalone from "pub4/pwa_standalone"
import BatteryAware from "pub4/battery_aware"
import NetworkAware from "pub4/network_aware"
import ViewportAware from "pub4/viewport_aware"
import Haptics from "pub4/haptics"
import Geolocation from "pub4/geolocation"
import BottomSheet from "pub4/bottom_sheet"

const COMPONENT_REGISTRATIONS = [
  [ "auto-submit", AutoSubmit ],
  [ "character-counter", CharacterCounter ],
  [ "clipboard", Clipboard ],
  [ "toast", Notification ],
  [ "read-more", ReadMore ],
  [ "reveal", Reveal ],
  [ "password-visibility", PasswordVisibility ],
  [ "popover", Popover ],
]

export function bootPub4Stimulus(application) {
  noteSession()

  application.register("live-search", LiveSearch)
  application.register("search-focus", SearchFocus)
  application.register("offline-page", OfflinePage)
  application.register("install-prompt", InstallPrompt)
  application.register("cookie-consent", CookieConsent)
  application.register("welcome-onboarding", WelcomeOnboarding)
  application.register("newsletter-capture", NewsletterCapture)
  application.register("link-converter", LinkConverter)
  application.register("theme-toggle", ThemeToggle)
  application.register("infinite-scroll", InfiniteScroll)
  application.register("scroll-reveal", ScrollReveal)
  application.register("nav-autohide", NavAutohide)
  application.register("action", ActionController)
  application.register("tiptap-editor", TiptapEditor)
  application.register("feed-hotkey", FeedHotkey)
  application.register("nearby-chat", NearbyChat)
  application.register("offline-feed", OfflineFeed)
  application.register("pwa-standalone", PwaStandalone)
  application.register("battery-aware", BatteryAware)
  application.register("network-aware", NetworkAware)
  application.register("viewport-aware", ViewportAware)
  application.register("haptics", Haptics)
  application.register("geolocation", Geolocation)
  application.register("bottom-sheet", BottomSheet)
  application.register("parallax-tilt", ParallaxTilt)

  COMPONENT_REGISTRATIONS.forEach(([ name, component ]) => {
    if (component) application.register(name, component)
  })

  StimulusReflex.initialize(application, {
    applicationController: ApplicationController,
    isolate: true
  })
}
