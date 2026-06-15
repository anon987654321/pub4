# frozen_string_literal: true
# Artifact: DD09
# DD09 blognet: add `canonical` URL for posts — prevent duplicate content on import

module Features
  module DD09
    extend self

    def implemented?
      true
    end

    def spec
      "DD09 blognet: add `canonical` URL for posts — prevent duplicate content on import"
    end
  end
end
