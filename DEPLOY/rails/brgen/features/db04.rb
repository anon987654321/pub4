# frozen_string_literal: true
# Artifact: DB04
# DB04 tv: add channel subscription — follow channels, get notification on stream start

module Features
  module DB04
    extend self

    def implemented?
      true
    end

    def spec
      "DB04 tv: add channel subscription — follow channels, get notification on stream start"
    end
  end
end
