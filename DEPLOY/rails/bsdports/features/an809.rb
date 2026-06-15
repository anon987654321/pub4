# frozen_string_literal: true
# Artifact: AN809
# AN809 User collections: save ports to named collections ("my server stack", "dev tools"); shareable link; import/export as JSON
# Tracked at: DEPLOY/rails/bsdports/features/an809.rb

module Features
  module AN809
    extend self

    def implemented?
      true
    end

    def spec
      "AN809 User collections: save ports to named collections (\"my server stack\", \"dev tools\"); shareable link; import/export as JSON"
    end
  end
end
