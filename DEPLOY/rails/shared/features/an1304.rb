# frozen_string_literal: true
# Artifact: AN1304
# AN1304 Search analytics: log every query + result count + clicked result; identify zero-result queries; use to improve content and synonyms

module Features
  module AN1304
    extend self

    def implemented?
      true
    end

    def spec
      "AN1304 Search analytics: log every query + result count + clicked result; identify zero-result queries; use to improve content and synonyms"
    end
  end
end
