import AutoSubmit from "@stimulus-components/auto-submit"
import CharacterCounter from "@stimulus-components/character-counter"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Clipboard from "@stimulus-components/clipboard"
import ContentLoader from "@stimulus-components/content-loader"
import Dialog from "@stimulus-components/dialog"
import Dropdown from "@stimulus-components/dropdown"
import Hotkey from "@stimulus-components/hotkey"
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

import ScrollProgress from "controllers/scroll_progress_controller"
import Toast from "controllers/toast_controller"
import Map from "controllers/map_controller"
import PwaInstall from "controllers/pwa_install_controller"
import PwaStandalone from "controllers/pwa_standalone_controller"
import OfflineFeed from "controllers/offline_feed_controller"
import OfflineFeedCache from "controllers/offline_feed_cache_controller"
import OfflineDraft from "controllers/offline_draft_controller"
import OfflineSync from "controllers/offline_sync_controller"
import SwUpdate from "controllers/sw_update_controller"
import WakeLock from "controllers/wake_lock_controller"
import OrientationLock from "controllers/orientation_lock_controller"
import InfiniteScroll from "controllers/infinite_scroll_controller"
import PullToRefresh from "controllers/pull_to_refresh_controller"
import Swipe from "controllers/swipe_controller"
import BottomSheet from "controllers/bottom_sheet_controller"
import LazyImage from "controllers/lazy_image_controller"
import Autosave from "controllers/autosave_controller"
import Toggle from "controllers/toggle_controller"
import Tabs from "controllers/tabs_controller"
import OptimisticUi from "controllers/optimistic_ui_controller"
import TurboFormValidation from "controllers/turbo_form_validation_controller"
import TurboNativeBridge from "controllers/turbo_native_bridge_controller"
import Datepicker from "controllers/datepicker_controller"
import BlurHash from "controllers/blur_hash_controller"

const COMPONENTS = {
  "auto-submit": AutoSubmit,
  "character-counter": CharacterCounter,
  "checkbox-select-all": CheckboxSelectAll,
  clipboard: Clipboard,
  "content-loader": ContentLoader,
  dialog: Dialog,
  dropdown: Dropdown,
  hotkey: Hotkey,
  notification: Notification,
  popover: Popover,
  "read-more": ReadMore,
  reveal: Reveal,
  "scroll-to": ScrollTo,
  sortable: Sortable,
  sound: Sound,
  "speech-recognition": SpeechRecognition,
  "textarea-autogrow": TextareaAutogrow,
  timeago: Timeago,
  "scroll-progress": ScrollProgress,
  toast: Toast,
  map: Map,
  "pwa-install": PwaInstall,
  "pwa-standalone": PwaStandalone,
  "offline-feed": OfflineFeed,
  "offline-feed-cache": OfflineFeedCache,
  "offline-draft": OfflineDraft,
  "offline-sync": OfflineSync,
  "sw-update": SwUpdate,
  "wake-lock": WakeLock,
  "orientation-lock": OrientationLock,
  "infinite-scroll": InfiniteScroll,
  "pull-to-refresh": PullToRefresh,
  swipe: Swipe,
  "bottom-sheet": BottomSheet,
  "lazy-image": LazyImage,
  autosave: Autosave,
  toggle: Toggle,
  tabs: Tabs,
  "optimistic-ui": OptimisticUi,
  "turbo-form-validation": TurboFormValidation,
  "turbo-native-bridge": TurboNativeBridge,
  datepicker: Datepicker,
  "blur-hash": BlurHash
}

export function registerStimulusComponents(application) {
  Object.entries(COMPONENTS).forEach(([name, controller]) => {
    application.register(name, controller)
  })
}

export default registerStimulusComponents