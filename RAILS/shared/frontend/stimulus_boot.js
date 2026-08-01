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
import SearchFocus from "pub4/search_focus"
import OfflinePage from "pub4/offline_page"
import InstallPrompt from "pub4/install_prompt"
import ThemeToggle from "pub4/theme_toggle"
import InfiniteScroll from "pub4/infinite_scroll"
import BrowserFingerprint from "pub4/browser_fingerprint"
import DirectUpload from "pub4/direct_upload"
import CharacterCounter from "pub4/character_counter"
import LuxuryProduct from "pub4/luxury_product"
import ScrollReveal from "pub4/scroll_reveal"
import ScrollChrome from "pub4/scroll_chrome"
import BrgenShell from "pub4/brgen_shell"
import ActionController from "pub4/action"
import BottomSheet from "pub4/bottom_sheet"
import Autosave from "pub4/autosave"
import DraftStore from "pub4/draft_store"
import MediaPicker from "pub4/media_picker"
import FeedCompose from "pub4/feed_compose"
import FeedHotkey from "pub4/feed_hotkey"
import EdgeSwiper from "pub4/edge_swiper"
import NearbyChat from "pub4/nearby_chat"
import ConversationLog from "pub4/conversation_log"
import Presence from "pub4/presence"

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
  application.register("search-focus", SearchFocus)
  application.register("offline-page", OfflinePage)
  application.register("install-prompt", InstallPrompt)
  application.register("theme-toggle", ThemeToggle)
  application.register("infinite-scroll", InfiniteScroll)
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("luxury-product", LuxuryProduct)
  application.register("scroll-reveal", ScrollReveal)
  application.register("scroll-chrome", ScrollChrome)
  application.register("brgen-shell", BrgenShell)
  application.register("action", ActionController)
  application.register("bottom-sheet", BottomSheet)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)
  application.register("feed-hotkey", FeedHotkey)
  application.register("edge-swiper", EdgeSwiper)
  application.register("nearby-chat", NearbyChat)
  application.register("conversation-log", ConversationLog)
  application.register("presence", Presence)

  COMPONENT_REGISTRATIONS.forEach(([name, component]) => {
    if (component) application.register(name, component)
  })

  StimulusReflex.initialize(application, {
    applicationController: ApplicationController,
    isolate: true
  })

  if (futurism) {
    import("@stimulus_reflex/futurism")
      .then((mod) => {
        const Futurism = mod?.default || mod?.Futurism || mod
        // Stimulus Application.load reads definition.identifier / shouldLoad — undefined crashes boot.
        if (Futurism && (typeof Futurism === "function" || Futurism.shouldLoad !== undefined || Futurism.prototype)) {
          application.register("futurism", Futurism)
        }
      })
      .catch(() => {
        /* optional dependency — vertical surfaces still boot without Futurism */
      })
  }
}
