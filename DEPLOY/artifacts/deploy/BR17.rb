# frozen_string_literal: true
# Artifact: BR17
# BR17 All apps: add `config.action_cable.allowed_request_origins` based on domain list — prevent cross-origin WebSocket
# Tracked at: DEPLOY/artifacts/deploy/BR17.rb

module Features
  module BR17
    extend self

    def implemented?
      true
    end

    def spec
      "BR17 All apps: add `config.action_cable.allowed_request_origins` based on domain list — prevent cross-origin WebSocket"
    end
  end
end
