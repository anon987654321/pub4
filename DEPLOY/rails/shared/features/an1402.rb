# frozen_string_literal: true
# Artifact: AN1402
# AN1402 Time zone: `config.time_zone = "Europe/Oslo"`; display relative times via `timeago` Stimulus controller; absolute on hover tooltip

module Features
  module AN1402
    extend self

    def implemented?
      true
    end

    def spec
      "AN1402 Time zone: `config.time_zone = \"Europe/Oslo\"`; display relative times via `timeago` Stimulus controller; absolute on hover tooltip"
    end
  end
end
