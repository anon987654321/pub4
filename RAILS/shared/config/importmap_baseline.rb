# frozen_string_literal: true

# Shared importmap pins for the pub4 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

sc_vendor = Shared::Engine.root.join("vendor/javascript")
sc_pin = lambda do |name|
  pin "@stimulus-components/#{name}", to: sc_vendor.join("@stimulus-components--#{name}.js").to_s
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/request.js", to: "@rails--request.js.js"
pin "stimulus-use"
pin "stimulus_reflex"
pin "cable_ready"
pin "@stimulus_reflex/futurism"
pin "date-fns"
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

%w[
  animated-number auto-submit character-counter checkbox-select-all clipboard
  content-loader dialog dropdown hotkey lightbox notification popover read-more
  reveal scroll-to sortable sound speech-recognition timeago password-visibility
  rails-nested-form carousel
].each { |name| sc_pin.call(name) }

pin "@stimulus-components/textarea-autogrow", to: sc_vendor.join("@stimulus-components--textarea-autogrow.js").to_s
pin "stimulus-textarea-autogrow", to: sc_vendor.join("@stimulus-components--textarea-autogrow.js").to_s