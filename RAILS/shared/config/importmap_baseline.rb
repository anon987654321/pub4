# frozen_string_literal: true

# Shared importmap pins for the pub4 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

sc_pin = lambda do |name, preload: true|
  pin "@stimulus-components/#{name}", to: "@stimulus-components--#{name}.js", preload: preload
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Vendored, not CDN. The dist build is what makes that possible: src/index.js
# pulls in ./fetch_request, ./fetch_response, ./request_interceptor and ./verbs
# via *extensionless* relative imports — valid for a bundler, which auto-resolves
# the .js, but not for a browser's native ES module loader, which requests the
# literal path and 404s. dist/requestjs.js is pre-bundled with no imports at all.
pin "@rails/request.js", to: "@rails--request.js"
# The cable_ready gem ships its own importmap pinning morphdom to ga.jspm.io,
# with `pin`'s default preload: true — measured on live brgen.no, that host and
# jsDelivr were the two external modulepreloads on every page. This line runs
# after the gem paths are drawn, so re-pinning the same name overrides it.
pin "morphdom", to: "morphdom.js"
pin "stimulus-use"
pin "stimulus_reflex"
pin "cable_ready"
# No futurism pin. It used to be here — `pin "@stimulus_reflex/futurism", to:
# "futurism.min.js"`, aliasing the scoped npm name stimulus_boot.js imported to
# the asset the gem itself ships. The alias was correct and the module resolved
# and registered on every page. What it never had was a consumer: no ERB in any
# app carries data-controller="futurism", and shared/_futurism_pagy_list.html.erb
# (the one place that would have) had zero callers. `pin` defaults to
# preload: true, so the whole thing was fetched eagerly on every page load to
# register a controller nothing asked for. Registration and partial removed with
# it. The `futurism` gem stays in all three Gemfiles for the server-side
# `futurize` helper; wiring a real paginated index to it is the open lazy-render
# work in FINAL_TODO P0.4, and that starts by putting this pin back.
# No date-fns pin, and unpkg.com is no longer contacted by any app. It existed
# for one consumer, @stimulus-components/timeago, and that controller is gone:
# it reads data-timeago-datetime-value, no view in any app ever set one, and its
# only possible effect was to overwrite the server's localised Norwegian with
# date-fns English. Relative time is now rendered server-side by
# Shared::UiHelper#time_ago. Restoring the pin means restoring the CDN, because
# date-fns's ESM build cross-references ~200 siblings by *relative* path
# (./addDays.js, ./formatDistance.js, ...) — vendoring one flattened file breaks
# every one of those paths once served from our own domain.
#
# preload: false on every CDN-backed pin from here down. `pin` defaults to
# preload: true, so each emitted a <link rel="modulepreload"> on every page of
# every app -- jsDelivr and esm.sh on the first-paint critical path whether or
# not any code on the page imported them. stimulus_boot.js registers carousel on
# demand; without this the preload fetched it anyway and the deferral bought
# nothing.
pin "sortablejs"
pin "pub4/hotwire", to: "hotwire.js"
pin "pub4/stimulus_boot", to: "stimulus_boot.js"
pin "pub4/live_search", to: "live_search_controller.js"
pin "pub4/search_focus", to: "search_focus_controller.js"
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
pin "pub4/nearby_chat", to: "nearby_chat_controller.js"
pin "pub4/conversation_log", to: "conversation_log_controller.js"
pin "pub4/optimistic_send", to: "optimistic_send_controller.js"
pin "pub4/presence", to: "presence_controller.js"
pin "pub4/scroll_chrome", to: "scroll_chrome_controller.js"
pin "pub4/brgen_shell", to: "brgen_shell_controller.js"
pin "pub4/action", to: "action_controller.js"
pin "pub4/bottom_sheet", to: "bottom_sheet_controller.js"
pin "pub4/dismiss", to: "dismiss_controller.js"
# 1% sample (hotwire.js WEB_VITALS_SAMPLE_RATE), with a local PerformanceObserver
# fallback -- so 99 visitors in 100 never import this and none of them should
# preload it.
pin "web-vitals", to: "https://cdn.jsdelivr.net/npm/web-vitals@4.2.4/dist/web-vitals.js", preload: false
pin "pub4/autosave", to: "autosave_controller.js"
pin "pub4/draft_store", to: "draft_store_controller.js"
pin "pub4/media_picker", to: "media_picker_controller.js"
pin "pub4/feed_compose", to: "feed_compose_controller.js"
pin "pub4/feed_hotkey", to: "feed_hotkey_controller.js"
pin "pub4/offline_feed", to: "offline_feed_controller.js"
pin "pub4/pwa_standalone", to: "pwa_standalone_controller.js"
pin "pub4/outbound_click", to: "outbound_click_controller.js"
# Not a controller — the shared ordering rule for the three onboarding prompts.
pin "pub4/onboarding", to: "onboarding_queue.js"
pin "pub4/battery_aware", to: "battery_aware_controller.js"
pin "pub4/network_aware", to: "network_aware_controller.js"
pin "pub4/haptics", to: "haptics_controller.js"
pin "pub4/geolocation", to: "geolocation_controller.js"
pin "pwa/offline_store", to: "pwa_offline_store.js"
# Only @stimulus-components/carousel imports this, and carousel appears on one
# surface in the whole family (amber shared/_wardrobe_showcase). Lazy-registered
# in stimulus_boot.js.
pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11.1.15/swiper-bundle.min.mjs", preload: false
# @stimulus-components/lightbox imports this; only brgen pinned it locally,
# so every other app using this shared baseline couldn't resolve it.
pin "lightgallery", to: "lightgallery.js"
# amber's autosave/draft_store controllers import this directly; only brgen
# pinned it locally (from app/javascript/, not vendor/javascript/, but the
# content itself has no external deps so it moves here just as cleanly).
pin "idb-keyval", to: "idb-keyval.js"

# dialog, scroll-to, sound and speech-recognition were pinned, vendored,
# imported and registered, and no ERB in any of the four apps carries a
# data-controller for them -- four components shipped and preloaded on every page
# so that nothing could use them. Dropped from stimulus_boot.js with these pins.
%w[
  animated-number auto-submit character-counter checkbox-select-all clipboard
  content-loader dropdown hotkey lightbox notification read-more
  reveal sortable password-visibility rails-nested-form
].each { |name| sc_pin.call(name) }

# Registered on demand by stimulus_boot.js -- its dependency is the swiper CDN
# pin above. Pinned so the dynamic import() can resolve, not preloaded.
%w[carousel].each { |name| sc_pin.call(name, preload: false) }

pin "@stimulus-components/textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"
pin "stimulus-textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"
