# frozen_string_literal: true
# Artifact: AN1705
# AN1705 pluck over map: replace `Model.all.map(&:column)` with `Model.pluck(:column)` — 10x faster, bypasses model instantiation

module Features
  module AN1705
    extend self

    def implemented?
      true
    end

    def spec
      "AN1705 pluck over map: replace `Model.all.map(&:column)` with `Model.pluck(:column)` — 10x faster, bypasses model instantiation"
    end
  end
end
