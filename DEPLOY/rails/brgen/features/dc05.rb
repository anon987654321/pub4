# frozen_string_literal: true
# Artifact: DC05
# DC05 marketplace: add "reserved" status — seller can mark listing while in negotiation

module Features
  module DC05
    extend self

    def implemented?
      true
    end

    def spec
      "DC05 marketplace: add \"reserved\" status — seller can mark listing while in negotiation"
    end
  end
end
