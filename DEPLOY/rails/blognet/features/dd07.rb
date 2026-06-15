# frozen_string_literal: true
# Artifact: DD07
# DD07 blognet: add reading time estimate (`ceil(word_count / 200)` minutes)

module Features
  module DD07
    extend self

    def implemented?
      true
    end

    def spec
      "DD07 blognet: add reading time estimate (`ceil(word_count / 200)` minutes)"
    end
  end
end
