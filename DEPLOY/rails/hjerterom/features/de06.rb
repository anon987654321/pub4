# frozen_string_literal: true
# Artifact: DE06
# DE06 hjerterom: add collection confirmation — both parties confirm handoff, closes listing

module Features
  module DE06
    extend self

    def implemented?
      true
    end

    def spec
      "DE06 hjerterom: add collection confirmation — both parties confirm handoff, closes listing"
    end
  end
end
