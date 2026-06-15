# frozen_string_literal: true
# Artifact: AN1715
# AN1715 config.relative_url_root for subapps: if mounting multiple apps under one domain via relayd, set `config.relative_url_root = "/app_name"` to fix all asset path generation

module Features
  module AN1715
    extend self

    def implemented?
      true
    end

    def spec
      "AN1715 config.relative_url_root for subapps: if mounting multiple apps under one domain via relayd, set `config.relative_url_root = \"/app_name\"` to fix all asset path generation"
    end
  end
end
