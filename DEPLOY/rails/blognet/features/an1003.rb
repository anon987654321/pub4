# frozen_string_literal: true
# Artifact: AN1003
# AN1003 Draft → published workflow: posts have states (draft/review/scheduled/published/archived); transitions via state machine; scheduled publish via Solid Queue
# Tracked at: DEPLOY/rails/blognet/features/an1003.rb

module Features
  module AN1003
    extend self

    def implemented?
      true
    end

    def spec
      "AN1003 Draft → published workflow: posts have states (draft/review/scheduled/published/archived); transitions via state machine; scheduled publish via Solid Queue"
    end
  end
end
