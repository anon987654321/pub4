# frozen_string_literal: true

require "rails/engine"
require "shared/vertical_engine"

module BrgenMessenger
  # The boot shape every vertical shares, which is what puts app/javascript on
  # the asset path. Without it the typing, composer and voice-note controllers
  # were files nothing could import, and Enter-to-send, the typing indicator and
  # voice notes did nothing in a browser.
  class Engine < ::Rails::Engine
    include Shared::VerticalEngine
  end
end
