// Registers @stimulus-components baseline + StimulusReflex (+ optional Futurism).
import AutoSubmit from "@stimulus-components/auto-submit"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Clipboard from "@stimulus-components/clipboard"
import Dropdown from "@stimulus-components/dropdown"
import Lightbox from "@stimulus-components/lightbox"
import Notification from "@stimulus-components/notification"
import ReadMore from "@stimulus-components/read-more"
import Reveal from "@stimulus-components/reveal"
import Sortable from "@stimulus-components/sortable"
import TextareaAutogrow from "@stimulus-components/textarea-autogrow"
import AnimatedNumber from "@stimulus-components/animated-number"
import PasswordVisibility from "@stimulus-components/password-visibility"
import Popover from "@stimulus-components/popover"
import RailsNestedForm from "@stimulus-components/rails-nested-form"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"
import LiveSearch from "pub4/live_search"
import SearchFocus from "pub4/search_focus"
import OfflinePage from "pub4/offline_page"
import InstallPrompt from "pub4/install_prompt"
import { noteSession } from "pub4/onboarding"
import ThemeToggle from "pub4/theme_toggle"
import InfiniteScroll from "pub4/infinite_scroll"
import BrowserFingerprint from "pub4/browser_fingerprint"
import DirectUpload from "pub4/direct_upload"
import OutboundClick from "pub4/outbound_click"
import CharacterCounter from "pub4/character_counter"
import LuxuryProduct from "pub4/luxury_product"
import ParallaxTilt from "pub4/parallax_tilt"
import ScrollReveal from "pub4/scroll_reveal"
import ScrollChrome from "pub4/scroll_chrome"
import BrgenShell from "pub4/brgen_shell"
import NavAutohide from "pub4/nav_autohide"
import ActionController from "pub4/action"
import BottomSheet from "pub4/bottom_sheet"
import Dismiss from "pub4/dismiss"
import Autosave from "pub4/autosave"
import DraftStore from "pub4/draft_store"
import MediaPicker from "pub4/media_picker"
import FeedCompose from "pub4/feed_compose"
import TiptapEditor from "pub4/tiptap_editor"
import FeedHotkey from "pub4/feed_hotkey"
import EdgeSwiper from "pub4/edge_swiper"
import SearchPalette from "pub4/search_palette"
import NearbyChat from "pub4/nearby_chat"
import ConversationLog from "pub4/conversation_log"
import OptimisticSend from "pub4/optimistic_send"
import Presence from "pub4/presence"
import OfflineFeed from "pub4/offline_feed"
import PwaStandalone from "pub4/pwa_standalone"
import BatteryAware from "pub4/battery_aware"
import NetworkAware from "pub4/network_aware"
import MediaExclusive from "pub4/media_exclusive"
import Haptics from "pub4/haptics"
import Geolocation from "pub4/geolocation"
import ViewportAware from "pub4/viewport_aware"

const COMPONENT_REGISTRATIONS = [
  ["auto-submit", AutoSubmit],
  ["character-counter", CharacterCounter],
  ["checkbox-select-all", CheckboxSelectAll],
  ["clipboard", Clipboard],
  // content-loader retired 2026-08-21, the timeago precedent: zero call
  // sites, and a turbo-frame stack does its job natively — a lazy frame
  // shows its skeleton children until the fetch lands.
  ["dropdown", Dropdown],
  ["lightbox", Lightbox],
  ["toast", Notification],
  ["read-more", ReadMore],
  ["reveal", Reveal],
  ["sortable", Sortable],
  ["textarea-autogrow", TextareaAutogrow],
  ["animated-number", AnimatedNumber],
  ["password-visibility", PasswordVisibility],
  // Vendored since the 2014 tooltip port, never registered — the feed-action
  // tooltips (_popover_tooltip.scss) waited for this line.
  ["popover", Popover],
  ["nested-form", RailsNestedForm],
]

// The one component whose dependency is a third-party CDN, registered only on
// pages that actually contain it.
//
// carousel pulls swiper from cdn.jsdelivr.net, and it was a static import here
// -- so every page of all three apps put that host on its first-paint critical
// path. Measured on the brgen front page: 537 requests for one load, including
// the whole swiper@11.1.15/shared + modules tree. ES modules fail as a graph,
// so one slow or blocked CDN left window.Turbo undefined and all 169
// data-controller elements on that page inert.
//
// The importmap pin stays on the CDN deliberately: importmap_baseline.rb
// documents why (swiper cross-references siblings by *relative* path, so a
// single vendored file breaks every one of those paths). Keeping the pin and
// deferring the import fixes the critical path without reopening that decision.
//
// "carousel" here means this one swiper-backed package, and the only element
// asking for it is amber's shared/_wardrobe_showcase. It does NOT mean brgen has
// no carousels -- brgen's are hand-rolled and touch neither this controller nor
// swiper: the media gallery and dating swipe (swipe_controller,
// data-swipe-mode-value="carousel"). So the deferral costs brgen nothing today,
// but adopting this package on any brgen surface puts jsdelivr back on that
// page -- vendor swiper first if that happens.
//
// timeago was the second entry here until 2026-08-12. It read
// data-timeago-datetime-value; no view in any app ever set that attribute, so
// on the eighteen surfaces that declared the controller it replaced the
// server's text with the empty string -- or would have, had it registered.
// Measured over CDP on the live post page: all three elements kept their
// server-rendered text. Its only possible effect was to overwrite localised
// Norwegian with date-fns English, so the controller, the eighteen
// declarations and the date-fns pin all went together.
//
// jox-logo is here for the opposite reason: not a CDN cost but a product one.
// amber and bsdports share the animated logo mark and brgen has no such logo,
// so a static import would ship branding to an app that cannot render it. Lazy
// registration costs brgen one importmap line and no fetch.
const LAZY_COMPONENTS = [
  ["carousel", () => import("@stimulus-components/carousel")],
  ["jox-logo", () => import("pub4/jox_logo")]
]

// Register `name` the first time the document contains an element asking for it.
// Checks now, on every Turbo navigation, and on DOM mutation, so controllers
// arriving by turbo-stream are covered too.
const registerWhenPresent = (application, name, load) => {
  const selector = `[data-controller~="${name}"]`
  let done = false
  let observer = null

  const stop = () => {
    document.removeEventListener("turbo:load", attempt)
    document.removeEventListener("turbo:frame-load", attempt)
    if (observer) { observer.disconnect(); observer = null }
  }

  function attempt() {
    if (done || !document.querySelector(selector)) return
    done = true
    stop()
    load()
      .then((mod) => {
        const constructor = mod?.default || mod
        if (constructor) application.register(name, constructor)
      })
      .catch(() => {
        // Optional: the surface degrades to its server-rendered markup. Allow a
        // later attempt rather than latching the failure for the session.
        done = false
        listen()
      })
  }

  function listen() {
    document.addEventListener("turbo:load", attempt)
    document.addEventListener("turbo:frame-load", attempt)
    if (!observer && typeof MutationObserver === "function") {
      observer = new MutationObserver(attempt)
      observer.observe(document.documentElement, { childList: true, subtree: true })
    }
  }

  attempt()
  if (!done) listen()
}

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
  application.register("media-exclusive", MediaExclusive)
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("outbound-click", OutboundClick)
  application.register("luxury-product", LuxuryProduct)
  application.register("scroll-reveal", ScrollReveal)
  application.register("scroll-chrome", ScrollChrome)
  application.register("brgen-shell", BrgenShell)
  application.register("nav-autohide", NavAutohide)
  application.register("action", ActionController)
  application.register("bottom-sheet", BottomSheet)
  application.register("dismiss", Dismiss)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)
  application.register("tiptap-editor", TiptapEditor)
  application.register("feed-hotkey", FeedHotkey)
  application.register("edge-swiper", EdgeSwiper)
  application.register("search-palette", SearchPalette)
  application.register("nearby-chat", NearbyChat)
  application.register("conversation-log", ConversationLog)
  application.register("optimistic-send", OptimisticSend)
  application.register("presence", Presence)
  application.register("offline-feed", OfflineFeed)
  application.register("pwa-standalone", PwaStandalone)
  application.register("battery-aware", BatteryAware)
  application.register("network-aware", NetworkAware)
  application.register("haptics", Haptics)
  application.register("geolocation", Geolocation)
  application.register("viewport-aware", ViewportAware)
  // The in-feed affiliate band tilts under the pointer. Registered here rather
  // than in one app since the band itself is shared now.
  application.register("parallax-tilt", ParallaxTilt)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => {
    if (component) application.register(name, component)
  })

  LAZY_COMPONENTS.forEach(([name, load]) => registerWhenPresent(application, name, load))

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
