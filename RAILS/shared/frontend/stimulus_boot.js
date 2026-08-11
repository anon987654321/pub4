// Registers @stimulus-components baseline + StimulusReflex (+ optional Futurism).
import AutoSubmit from "@stimulus-components/auto-submit"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Clipboard from "@stimulus-components/clipboard"
import ContentLoader from "@stimulus-components/content-loader"
import Dropdown from "@stimulus-components/dropdown"
import Hotkey from "@stimulus-components/hotkey"
import Lightbox from "@stimulus-components/lightbox"
import Notification from "@stimulus-components/notification"
import ReadMore from "@stimulus-components/read-more"
import Reveal from "@stimulus-components/reveal"
import Sortable from "@stimulus-components/sortable"
import TextareaAutogrow from "@stimulus-components/textarea-autogrow"
import AnimatedNumber from "@stimulus-components/animated-number"
import PasswordVisibility from "@stimulus-components/password-visibility"
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
import ScrollReveal from "pub4/scroll_reveal"
import ScrollChrome from "pub4/scroll_chrome"
import BrgenShell from "pub4/brgen_shell"
import ActionController from "pub4/action"
import BottomSheet from "pub4/bottom_sheet"
import Dismiss from "pub4/dismiss"
import Autosave from "pub4/autosave"
import DraftStore from "pub4/draft_store"
import MediaPicker from "pub4/media_picker"
import FeedCompose from "pub4/feed_compose"
import FeedHotkey from "pub4/feed_hotkey"
import EdgeSwiper from "pub4/edge_swiper"
import NearbyChat from "pub4/nearby_chat"
import ConversationLog from "pub4/conversation_log"
import OptimisticSend from "pub4/optimistic_send"
import Presence from "pub4/presence"
import OfflineFeed from "pub4/offline_feed"
import PwaStandalone from "pub4/pwa_standalone"

const COMPONENT_REGISTRATIONS = [
  ["auto-submit", AutoSubmit],
  ["character-counter", CharacterCounter],
  ["checkbox-select-all", CheckboxSelectAll],
  ["clipboard", Clipboard],
  ["content-loader", ContentLoader],
  ["dropdown", Dropdown],
  ["hotkey", Hotkey],
  ["lightbox", Lightbox],
  ["notification", Notification],
  ["toast", Notification],
  ["read-more", ReadMore],
  ["reveal", Reveal],
  ["sortable", Sortable],
  ["textarea-autogrow", TextareaAutogrow],
  ["animated-number", AnimatedNumber],
  ["password-visibility", PasswordVisibility],
  ["nested-form", RailsNestedForm],
]

// The two components whose dependency is a third-party CDN, registered only on
// pages that actually contain them.
//
// carousel pulls swiper from cdn.jsdelivr.net and timeago pulls date-fns from
// unpkg.com, and both were static imports here -- so every page of all three
// apps put those hosts on its first-paint critical path. Measured on the brgen
// front page: 537 requests for one load, including the whole
// swiper@11.1.15/shared + modules tree and the date-fns@4.4.0/_lib tree. ES
// modules fail as a graph, so one slow or blocked CDN left window.Turbo
// undefined and all 169 data-controller elements on that page inert.
//
// The importmap pins stay on the CDN deliberately: importmap_baseline.rb
// documents why (both packages cross-reference siblings by *relative* path, so
// a single vendored file breaks every one of those paths). Keeping the pin and
// deferring the import fixes the critical path without reopening that decision.
// carousel is amber-only (shared/_wardrobe_showcase); timeago appears on feed,
// message and notification surfaces but on no app's first paint.
const LAZY_COMPONENTS = [
  ["carousel", () => import("@stimulus-components/carousel")],
  ["timeago", () => import("@stimulus-components/timeago")]
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
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("outbound-click", OutboundClick)
  application.register("luxury-product", LuxuryProduct)
  application.register("scroll-reveal", ScrollReveal)
  application.register("scroll-chrome", ScrollChrome)
  application.register("brgen-shell", BrgenShell)
  application.register("action", ActionController)
  application.register("bottom-sheet", BottomSheet)
  application.register("dismiss", Dismiss)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)
  application.register("feed-hotkey", FeedHotkey)
  application.register("edge-swiper", EdgeSwiper)
  application.register("nearby-chat", NearbyChat)
  application.register("conversation-log", ConversationLog)
  application.register("optimistic-send", OptimisticSend)
  application.register("presence", Presence)
  application.register("offline-feed", OfflineFeed)
  application.register("pwa-standalone", PwaStandalone)

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
