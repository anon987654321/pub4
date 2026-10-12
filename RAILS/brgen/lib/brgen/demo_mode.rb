# frozen_string_literal: true

module Brgen
  # Synthetic community activity is for development/test or a visibly disclosed
  # demo deployment. Production does not opt in by default.
  module DemoMode
    module_function

    def disclosure_enabled?(env: ENV)
      env["BRGEN_DEMO_MODE"] == "1" &&
        env["BRGEN_DEMO_NOTICE"] == "1"
    end

    def seed_allowed?(environment: Rails.env.to_s, env: ENV)
      %w[development test].include?(environment.to_s) || disclosure_enabled?(env:)
    end
  end
end
