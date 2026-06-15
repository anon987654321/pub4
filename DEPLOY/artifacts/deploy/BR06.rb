# frozen_string_literal: true
# Artifact: BR06
# BR06 amber item upload: add `data-controller="direct-upload"` for background image processing
# Tracked at: DEPLOY/artifacts/deploy/BR06.rb

module Features
  module BR06
    extend self

    def implemented?
      true
    end

    def spec
      "BR06 amber item upload: add `data-controller=\"direct-upload\"` for background image processing"
    end
  end
end
