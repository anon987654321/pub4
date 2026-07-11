# frozen_string_literal: true

# Shared importmap pins for the pub4 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

sc_pin = lambda do |name|
  pin "@stimulus-components/#{name}", to: "@stimulus-components--#{name}.js"
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Same relative-import issue as date-fns below: index.js pulls in
# ./fetch_request, ./fetch_response, ./request_interceptor, ./verbs via
# relative paths, which only resolve when served from the same CDN directory.
pin "@rails/request.js", to: "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/index.js"
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
pin "pub4/theme_meta", to: "pub4_theme_meta.js"
pin "pub4/theme_toggle", to: "pub4_theme_toggle_controller.js"
pin "pub4/minimal_gesture", to: "minimal-gesture.js"
pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11.1.15/swiper-bundle.min.mjs"

%w[
  animated-number auto-submit character-counter checkbox-select-all clipboard
  content-loader dialog dropdown hotkey lightbox notification popover read-more
  reveal scroll-to sortable sound speech-recognition timeago password-visibility
  rails-nested-form carousel
].each { |name| sc_pin.call(name) }

pin "@stimulus-components/textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"
pin "stimulus-textarea-autogrow", to: "@stimulus-components--textarea-autogrow.js"