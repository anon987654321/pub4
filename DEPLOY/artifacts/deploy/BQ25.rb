# frozen_string_literal: true
# Artifact: BQ25
# BQ25 brgen: add `config.after_initialize` to load `sqlite-vec` extension if present (needed for distance queries)
# Tracked at: DEPLOY/artifacts/deploy/BQ25.rb

module Features
  module BQ25
    extend self

    def implemented?
      true
    end

    def spec
      "BQ25 brgen: add `config.after_initialize` to load `sqlite-vec` extension if present (needed for distance queries)"
    end
  end
end
