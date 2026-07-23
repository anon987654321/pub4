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
# stimulus_boot.js imports the scoped npm name (@stimulus_reflex/futurism),
# but the futurism gem's own importmap pins the bare "futurism" specifier to
# futurism.min.js — without `to:` here, importmap-rails looked for a literal
# "@stimulus_reflex/futurism.js" asset that doesn't exist, so the browser
# failed to resolve the bare specifier. Point our scoped alias at the same
# asset the gem itself ships.
pin "@stimulus_reflex/futurism", to: "futurism.min.js"
# date-fns's own ESM build cross-references ~200 sibling files via *relative*
# imports (./addDays.js, ./formatDistance.js, ...) rather than bare specifiers,
# so vendoring a single flattened file locally breaks every one of those
# relative paths once served from our own domain. Pinning straight to the CDN
# keeps the relative imports resolving against that same CDN path, matching
# the swiper/bundle pin below. Only stimulus-components/timeago needs this,
# for formatDistanceToNow.
pin "date-fns", to: "https://unpkg.com/date-fns@4.4.0/index.js"
pin "sortablejs"
pin "pub4/hotwire", to: "hotwire.js"
pin "pub4/stimulus_boot", to: "stimulus_boot.js"
pin "pub4/live_search", to: "live_search_controller.js"
pin "pub4/offline_page", to: "offline_page_controller.js"
pin "pub4/install_prompt", to: "install_prompt_controller.js"
pin "pub4/edge_swiper", to: "edge_swiper_controller.js"
pin "pub4/infinite_scroll", to: "infinite_scroll_controller.js"
pin "pub4/browser_fingerprint", to: "browser_fingerprint_controller.js"
pin "pub4/direct_upload", to: "direct_upload_controller.js"
pin "pub4/character_counter", to: "character_counter_controller.js"
pin "pub4/theme_meta", to: "theme_meta.js"
pin "pub4/theme_toggle", to: "theme_toggle_controller.js"
pin "pub4/luxury_product", to: "luxury_product_controller.js"
pin "pub4/scroll_reveal", to: "scroll_reveal_controller.js"
pin "pub4/scroll_chrome", to: "scroll_chrome_controller.js"
pin "pub4/brgen_shell", to: "brgen_shell_controller.js"
pin "pub4/action", to: "action_controller.js"
pin "pub4/bottom_sheet", to: "bottom_sheet_controller.js"
pin "web-vitals", to: "https://cdn.jsdelivr.net/npm/web-vitals@4.2.4/dist/web-vitals.js"
pin "pub4/autosave", to: "autosave_controller.js"
pin "pub4/draft_store", to: "draft_store_controller.js"
pin "pub4/media_picker", to: "media_picker_controller.js"
pin "pub4/feed_compose", to: "feed_compose_controller.js"
pin "pwa/offline_store", to: "pwa_offline_store.js"
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
