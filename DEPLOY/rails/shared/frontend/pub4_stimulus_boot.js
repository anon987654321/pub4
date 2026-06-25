// Registers @stimulus-components baseline + StimulusReflex (+ optional Futurism).
import AutoSubmit from "@stimulus-components/auto-submit"
import CharacterCounter from "@stimulus-components/character-counter"
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
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"
import LiveSearch from "pub4/live_search"
import OfflinePage from "pub4/offline_page"
import InstallPrompt from "pub4/install_prompt"
import ThemeToggle from "pub4/theme_toggle"

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
  ["timeago", Timeago]
]

export function bootPub4Stimulus(application, { futurism = true } = {}) {
  application.register("live-search", LiveSearch)
  application.register("offline-page", OfflinePage)
  application.register("install-prompt", InstallPrompt)
  application.register("theme-toggle", ThemeToggle)

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