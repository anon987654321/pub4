# frozen_string_literal: true
# Artifact: DE05
# DE05 hjerterom: add expiry alerts — notify givers 2h before food items expire (push + email)

module Features
  module DE05
    extend self

    def implemented?
      true
    end

    def spec
      "DE05 hjerterom: add expiry alerts — notify givers 2h before food items expire (push + email)"
    end
  end
end
