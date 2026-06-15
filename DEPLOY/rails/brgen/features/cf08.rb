# frozen_string_literal: true
# Artifact: CF08
# CF08 brgen: add pull-to-refresh gesture on feed (touch event + Turbo stream reload)

module Features
  module CF08
    extend self

    def implemented?
      true
    end

    def spec
      "CF08 brgen: add pull-to-refresh gesture on feed (touch event + Turbo stream reload)"
    end
  end
end
