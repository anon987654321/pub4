# frozen_string_literal: true

# Shared importmap pins for the pub4 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

sc_pin = lambda do |name|
  pin("@stimulus-components/#{name}", to: "@stimulus-components--#{name}.js")
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/request.js", to: "@rails--request.js"
pin "morphdom", to: "morphdom.js"
pin "stimulus-use"
pin "stimulus_reflex"
pin "cable_ready"
pin "sortablejs"
pin "tiptap", to: "tiptap.js", preload: false
pin "pub4/tiptap_editor", to: "tiptap_editor_controller.js"
pin "pub4/hotwire", to: "hotwire.js"
pin "pub4/pwa_runtime", to: "pwa_runtime.js"
pin "pub4/visual_field", to: "visual_field.js"
pin "pub4/visual_surface", to: "visual_surface_controller.js"
pin "pub4/stimulus_boot", to: "stimulus_boot.js"
pin "pub4/live_search", to: "live_search_controller.js"
pin "pub4/search_focus", to: "search_focus_controller.js"
pin "pub4/search_palette", to: "search_palette_controller.js"
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
pin "pub4/parallax_tilt", to: "parallax_tilt_controller.js"
pin "pub4/scroll_reveal", to: "scroll_reveal_controller.js"
pin "pub4/nearby_chat", to: "nearby_chat_controller.js"
pin "pub4/conversation_log", to: "conversation_log_controller.js"
pin "pub4/optimistic_send", to: "optimistic_send_controller.js"
pin "pub4/presence", to: "presence_controller.js"
pin "pub4/scroll_chrome", to: "scroll_chrome_controller.js"
pin "pub4/brgen_shell", to: "brgen_shell_controller.js"
pin "pub4/nav_autohide", to: "nav_autohide_controller.js"
pin "pub4/action", to: "action_controller.js"
pin "pub4/bottom_sheet", to: "bottom_sheet_controller.js"
pin "web-vitals", to: "https://cdn.jsdelivr.net/npm/web-vitals@4.2.4/dist/web-vitals.js", preload: false
pin "pub4/autosave", to: "autosave_controller.js"
pin "pub4/draft_store", to: "draft_store_controller.js"
pin "pub4/media_picker", to: "media_picker_controller.js"
pin "pub4/post_progressive", to: "post_progressive_controller.js"
pin "pub4/feed_compose", to: "feed_compose_controller.js"
pin "pub4/feed_hotkey", to: "feed_hotkey_controller.js"
pin "pub4/offline_feed", to: "offline_feed_controller.js"
pin "pub4/pwa_standalone", to: "pwa_standalone_controller.js"
pin "pub4/outbound_click", to: "outbound_click_controller.js"
pin "pub4/onboarding", to: "onboarding_queue.js"
pin "pub4/cookie_consent", to: "cookie_consent.js"
pin "pub4/cookie_consent_controller", to: "cookie_consent_controller.js"
pin "pub4/welcome_onboarding", to: "welcome_onboarding_controller.js"
pin "pub4/newsletter_capture", to: "newsletter_capture_controller.js"
pin "pub4/link_converter", to: "link_converter_controller.js"
pin "pub4/battery_aware", to: "battery_aware_controller.js"
pin "pub4/network_aware", to: "network_aware_controller.js"
pin "pub4/media_exclusive", to: "media_exclusive_controller.js"
pin "pub4/haptics", to: "haptics_controller.js"
pin "pub4/geolocation", to: "geolocation_controller.js"
pin "pub4/viewport_aware", to: "viewport_aware_controller.js"
pin "pwa/offline_store", to: "pwa_offline_store.js"
pin "lightgallery", to: "lightgallery.js"
pin "idb-keyval", to: "idb-keyval.js"

%w[
  animated-number auto-submit character-counter checkbox-select-all clipboard
  dropdown lightbox notification read-more reveal sortable password-visibility popover rails-nested-form
].each { |name| sc_pin.call(name) }
