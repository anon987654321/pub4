# frozen_string_literal: true
# Artifact: AN1601
# AN1601 Install StimulusReflex in all apps: `bundle add stimulus_reflex` + `rails stimulus_reflex:install`; configure ActionCable + CableReady; verify with `rails test:system`

module Features
  module AN1601
    extend self

    def implemented?
      true
    end

    def spec
      "AN1601 Install StimulusReflex in all apps: `bundle add stimulus_reflex` + `rails stimulus_reflex:install`; configure ActionCable + CableReady; verify with `rails test:system`"
    end
  end
end
