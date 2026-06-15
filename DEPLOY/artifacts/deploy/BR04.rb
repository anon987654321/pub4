# frozen_string_literal: true
# Artifact: BR04
# BR04 brgen TV: use `cable_ready.dispatch_event` to trigger live viewer count update every 10s
# Tracked at: DEPLOY/artifacts/deploy/BR04.rb

module Features
  module BR04
    extend self

    def implemented?
      true
    end

    def spec
      "BR04 brgen TV: use `cable_ready.dispatch_event` to trigger live viewer count update every 10s"
    end
  end
end
