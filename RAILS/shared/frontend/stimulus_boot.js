// Registers the controllers every app uses, plus @stimulus-components
// baseline entries and StimulusReflex. App-specific controllers live in
// stimulus_boot_social.js (brgen + amber), stimulus_boot_brgen.js and
// stimulus_boot_amber.js — each app's index.js calls only the boot
// functions it needs, so a controller with no view in an app is never
// imported there. Splitting these out is what makes that true: gating the
// application.register() call alone would not have, because a static
// `import` at the top of this file is fetched by every app that imports
// this module regardless of which registrations run.
import AutoSubmit from "@stimulus-components/auto-submit"
import Clipboard from "@stimulus-components/clipboard"
import Notification from "@stimulus-components/notification"
import ReadMore from "@stimulus-components/read-more"
import Reveal from "@stimulus-components/reveal"
import TextareaAutogrow from "@stimulus-components/textarea-autogrow"
import PasswordVisibility from "@stimulus-components/password-visibility"
import Popover from "@stimulus-components/popover"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"
import LiveSearch from "pub4/live_search"
import SearchFocus from "pub4/search_focus"
import OfflinePage from "pub4/offline_page"
import InstallPrompt from "pub4/install_prompt"
import { noteSession } from "pub4/onboarding"
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
  ["auto-submit", AutoSubmit],
  ["character-counter", CharacterCounter],
  ["clipboard", Clipboard],
  // content-loader retired 2026-08-21, the timeago precedent: zero call
  // sites, and a turbo-frame stack does its job natively — a lazy frame
  // shows its skeleton children until the fetch lands.
  ["toast", Notification],
  ["read-more", ReadMore],
  // No view mounts reveal. It stays because shared/frontend/examples.html.erb
  // offers it as a snippet, and SharedStimulusComponentsTest holds every
  // snippet to this table: a copied snippet must name a live controller.
  ["reveal", Reveal],
  ["textarea-autogrow", TextareaAutogrow],
  ["password-visibility", PasswordVisibility],
  // Vendored since the 2014 tooltip port, never registered — the feed-action
  // tooltips (_popover_tooltip.scss) waited for this line.
  ["popover", Popover],
]

export function bootPub4Stimulus(application) {
  // Counted once per boot, before any controller connects, so the three
  // onboarding prompts all read the same session number on this page. Safe on
  // every Turbo visit — it only increments after a gap. See pub4/onboarding.
  noteSession()

  application.register("live-search", LiveSearch)
  application.register("search-focus", SearchFocus)
  application.register("offline-page", OfflinePage)
  application.register("install-prompt", InstallPrompt)
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
  // Device-awareness controllers register as one set (DeviceAwarenessTest):
  // only brgen's views mount haptics and geolocation today, but they are
  // shared infrastructure alongside battery/network/viewport-aware, not
  // brgen-specific like search-palette or presence.
  application.register("haptics", Haptics)
  application.register("geolocation", Geolocation)
  // Only brgen's views mount the mobile sheet today; kept shared because it
  // is documented as shared infrastructure (design_contract_test.rb).
  application.register("bottom-sheet", BottomSheet)
  // The in-feed affiliate band tilts under the pointer. Registered here rather
  // than in one app since the band itself is shared now.
  application.register("parallax-tilt", ParallaxTilt)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => {
    if (component) application.register(name, component)
  })

  StimulusReflex.initialize(application, {
    applicationController: ApplicationController,
    isolate: true
  })

  // Futurism registration lived here and is gone. It resolved and registered
  // fine; nothing in any app ever carried data-controller="futurism", and the
  // pin it needed defaults to preload: true, so every page paid for a module
  // that had no element to attach to. See shared/config/importmap_baseline.rb
  // for the pin that came out with it, and what to restore if a real paginated
  // index adopts the lazy-render boundary.
}
