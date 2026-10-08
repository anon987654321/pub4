// Controllers only brgen's own views and engines mount. Split out of
// stimulus_boot.js so amber and bsdports never import these modules.
// See stimulus_boot.js for controllers every app registers, and
// stimulus_boot_social.js for the ones brgen shares with amber.
import BrgenShell from "pub4/brgen_shell"
import Dismiss from "pub4/dismiss"
import SearchPalette from "pub4/search_palette"
import ConversationLog from "pub4/conversation_log"
import OptimisticSend from "pub4/optimistic_send"
import Presence from "pub4/presence"
import PostProgressive from "pub4/post_progressive"
export function bootBrgenStimulus(application) {
  application.register("brgen-shell", BrgenShell)
  application.register("dismiss", Dismiss)
  application.register("search-palette", SearchPalette)
  application.register("conversation-log", ConversationLog)
  application.register("optimistic-send", OptimisticSend)
  application.register("presence", Presence)
  application.register("post-progressive", PostProgressive)


}
