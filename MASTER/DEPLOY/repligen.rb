# frozen_string_literal: true

module Bridges
  module Repligen
    MODEL_CATALOG = [
      {
        key: "repligen/krosflo-kr2i",
        name: "KrosFlo KR2i Tangential Flow Filtration System",
        manufacturer: "Repligen",
        category: "tff_system",
        tags: %w[tff filtration].freeze,
        url: "https://www.repligen.com/products/krosflo-kr2i"
      }.freeze,
      {
        key: "repligen/krosflo-kr2s",
        name: "KrosFlo KR2s Tangential Flow Filtration System",
        manufacturer: "Repligen",
        category: "tff_system",
        tags: %w[tff filtration].freeze,
        url: "https://www.repligen.com/products/krosflo-kr2s"
      }.freeze,
      {
        key: "repligen/xcell-atf",
        name: "XCell ATF System",
        manufacturer: "Repligen",
        category: "cell_retention",
        tags: %w[atf perfusion].freeze,
        url: "https://www.repligen.com/products/xcell-atf"
      }.freeze
    ].freeze

    def self.model_catalog = MODEL_CATALOG
  end
end