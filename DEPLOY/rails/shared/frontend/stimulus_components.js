import { Application } from "@hotwired/stimulus"

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

const application = Application.start()

application.register("auto-submit", AutoSubmit)
application.register("character-counter", CharacterCounter)
application.register("checkbox-select-all", CheckboxSelectAll)
application.register("clipboard", Clipboard)
application.register("content-loader", ContentLoader)
application.register("dialog", Dialog)
application.register("dropdown", Dropdown)
application.register("hotkey", Hotkey)
application.register("lightbox", Lightbox)
application.register("notification", Notification)
application.register("popover", Popover)
application.register("read-more", ReadMore)
application.register("reveal", Reveal)
application.register("scroll-to", ScrollTo)
application.register("sortable", Sortable)
application.register("sound", Sound)
application.register("speech-recognition", SpeechRecognition)
application.register("textarea-autogrow", TextareaAutogrow)
application.register("timeago", Timeago)

window.Stimulus = application
export { application }
