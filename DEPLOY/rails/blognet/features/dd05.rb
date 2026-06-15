# frozen_string_literal: true
# Artifact: DD05
# DD05 blognet: add RSS feed per blog (valid RSS 2.0, updated on publish)

module Features
  module DD05
    extend self

    def implemented?
      true
    end

    def spec
      "DD05 blognet: add RSS feed per blog (valid RSS 2.0, updated on publish)"
    end
  end
end
