# frozen_string_literal: true

# Shared importmap pins for the pub4 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

sc_pin = lambda do |name|
  pin "@stimulus-components/#{name}", to: "@stimulus-components--#{name}.js"
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# src/index.js pulls in ./fetch_request, ./fetch_response,
# ./request_interceptor, ./verbs via *extensionless* relative imports —
# valid for a bundler (which auto-resolves the .js) but not for a browser's
# native ES module loader, which requests the literal path with no
# extension and 404s. dist/requestjs.js is the pre-bundled, self-contained
# build (no imports at all) — use that instead.
pin "@rails/request.js", to: "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/dist/requestjs.js"
pin "stimulus-use"
pin "stimulus_reflex"
pin "cable_ready"
pin "@stimulus_reflex/futurism"
# date-fns's own ESM build cross-references ~200 sibling files via *relative*
# imports (./addDays.js, ./formatDistance.js, ...) rather than bare specifiers,
# so vendoring a single flattened file locally breaks every one of those
# relative paths once served from our own domain. Pinning straight to the CDN
# keeps the relative imports resolving against that same CDN path, matching
# the swiper/bundle pin below. Only stimulus-components/timeago needs this,
# for formatDistanceToNow.
pin "date-fns", to: "https://unpkg.com/date-fns@4.4.0/index.js"
pin "sortablejs"
pin "pub4/hotwire", to: "pub4_hotwire.js"
pin "pub4/stimulus_boot", to: "pub4_stimulus_boot.js"
pin "pub4/live_search", to: "pub4_live_search_controller.js"
pin "pub4/offline_page", to: "pub4_offline_page_controller.js"
pin "pub4/install_prompt", to: "pub4_install_prompt_controller.js"
pin "pub4/nav_reveal", to: "pub4_nav_reveal.js"
pin "pub4/infinite_scroll", to: "pub4_infinite_scroll_controller.js"
pin "pub4/browser_fingerprint", to: "pub4_browser_fingerprint_controller.js"
pin "pub4/direct_upload", to: "pub4_direct_upload_controller.js"
pin "pub4/character_counter", to: "pub4_character_counter_controller.js"
pin "pub4/theme_meta", to: "pub4_theme_meta.js"
pin "pub4/theme_toggle", to: "pub4_theme_toggle_controller.js"
pin "pub4/minimal_gesture", to: "minimal-gesture.js"
pin "pub4/luxury_product", to: "pub4_luxury_product_controller.js"
pin "pub4/scroll_reveal", to: "pub4_scroll_reveal_controller.js"
pin "pub4/x_action", to: "pub4_x_action_controller.js"
pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11.1.15/swiper-bundle.min.mjs"
# @stimulus-components/lightbox imports this; only brgen pinned it locally,
# so every other app using this shared baseline couldn't resolve it.
pin "lightgallery", to: "lightgallery.js"
# amber's autosave/draft_store controllers import this directly; only brgen
# pinned it locally (from app/javascript/, not vendor/javascript/, but the
# content itself has no external deps so it moves here just as cleanly).
pin "idb-keyval", to: "idb-keyval.js"

%w[
  animated-number auto-submit character-counter checkbox-select-all clipboard
  content-loader dialog dropdown hotkey lightbox notification popover read-more
  reveal scroll-to sortable sound speech-recognition timeago password-visibility
  rails-nested-form carousel
].each { |name| sc_pin.call(name) }

pin "@stimulus-components/textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"
pin "stimulus-textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"
