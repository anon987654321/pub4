# frozen_string_literal: true
# Artifact: AN1404
# AN1404 RTL readiness: CSS `[dir="rtl"]` overrides for any future Arabic/Hebrew locale; logical properties (`margin-inline-start`) instead of `margin-left` throughout

module Features
  module AN1404
    extend self

    def implemented?
      true
    end

    def spec
      "AN1404 RTL readiness: CSS `[dir=\"rtl\"]` overrides for any future Arabic/Hebrew locale; logical properties (`margin-inline-start`) instead of `margin-left` throughout"
    end
  end
end
