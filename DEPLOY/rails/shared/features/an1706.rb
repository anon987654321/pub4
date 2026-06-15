# frozen_string_literal: true
# Artifact: AN1706
# AN1706 pick for single value: replace `Model.where(x: y).limit(1).pluck(:z).first` with `Model.where(x: y).pick(:z)` — cleaner, same performance

module Features
  module AN1706
    extend self

    def implemented?
      true
    end

    def spec
      "AN1706 pick for single value: replace `Model.where(x: y).limit(1).pluck(:z).first` with `Model.where(x: y).pick(:z)` — cleaner, same performance"
    end
  end
end
