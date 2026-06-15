# frozen_string_literal: true
# Artifact: AN1405
# AN1405 Date format: Norwegian `dd.mm.yyyy` format in all date displays; ISO 8601 in API responses

module Features
  module AN1405
    extend self

    def implemented?
      true
    end

    def spec
      "AN1405 Date format: Norwegian `dd.mm.yyyy` format in all date displays; ISO 8601 in API responses"
    end
  end
end
