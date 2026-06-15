# frozen_string_literal: true
# Artifact: DB02
# DB02 tv: add live viewer count — Turbo Stream broadcast every 5s from Solid Cable

module Features
  module DB02
    extend self

    def implemented?
      true
    end

    def spec
      "DB02 tv: add live viewer count — Turbo Stream broadcast every 5s from Solid Cable"
    end
  end
end
