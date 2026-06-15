# frozen_string_literal: true

# Shared @stimulus-components pins — append to each app's config/importmap.rb
STIMULUS_COMPONENT_PINS = <<~RUBY
  pin "@stimulus-components/content-loader", to: "https://esm.sh/@stimulus-components/content-loader@1.0.1"
  pin "@stimulus-components/read-more", to: "https://esm.sh/@stimulus-components/read-more@5.0.0"
  pin "@stimulus-components/popover", to: "https://esm.sh/@stimulus-components/popover@1.0.0"
  pin "@stimulus-components/checkbox-select-all", to: "https://esm.sh/@stimulus-components/checkbox-select-all@1.0.0"
  pin "@stimulus-components/hotkey", to: "https://esm.sh/@stimulus-components/hotkey@1.0.0"
  pin "@stimulus-components/speech-recognition", to: "https://esm.sh/@stimulus-components/speech-recognition@1.0.0"
  pin "@stimulus-components/reveal", to: "https://esm.sh/@stimulus-components/reveal@5.0.0"
  pin "@stimulus-components/scroll-to", to: "https://esm.sh/@stimulus-components/scroll-to@5.0.0"
  pin "@stimulus-components/sound", to: "https://esm.sh/@stimulus-components/sound@1.0.0"
  pin "@stimulus-components/textarea-autogrow", to: "https://esm.sh/@stimulus-components/textarea-autogrow@5.0.0"
  pin "stimulus_components", to: "stimulus_components.js"
  pin "stimulus_components/register", to: "register_stimulus_components.js"
RUBY