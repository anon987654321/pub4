# frozen_string_literal: true
# Artifact: DE09
# DE09 hjerterom: add city isolation (same pattern as brgen — `acts_as_tenant`)

module Features
  module DE09
    extend self

    def implemented?
      true
    end

    def spec
      "DE09 hjerterom: add city isolation (same pattern as brgen — `acts_as_tenant`)"
    end
  end
end
