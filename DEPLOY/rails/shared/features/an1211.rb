# frozen_string_literal: true
# Artifact: AN1211
# AN1211 Font subsetting: subset system UI fonts; if custom font used, subset to Latin + Latin-Extended only; serve as woff2; `font-display: swap`
# Tracked at: DEPLOY/rails/shared/features/an1211.rb

module Features
  module AN1211
    extend self

    def implemented?
      true
    end

    def spec
      "AN1211 Font subsetting: subset system UI fonts; if custom font used, subset to Latin + Latin-Extended only; serve as woff2; `font-display: swap`"
    end
  end
end
