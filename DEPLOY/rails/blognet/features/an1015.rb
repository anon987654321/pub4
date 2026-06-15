# frozen_string_literal: true
# Artifact: AN1015
# AN1015 Collaborative editing: two authors co-edit via Turbo Stream paragraph locks — editing a paragraph locks it to others; releases after 30s inactivity
# Tracked at: DEPLOY/rails/blognet/features/an1015.rb

module Features
  module AN1015
    extend self

    def implemented?
      true
    end

    def spec
      "AN1015 Collaborative editing: two authors co-edit via Turbo Stream paragraph locks — editing a paragraph locks it to others; releases after 30s inactivity"
    end
  end
end
