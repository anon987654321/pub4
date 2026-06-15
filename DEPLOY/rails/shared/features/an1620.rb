# frozen_string_literal: true
# Artifact: AN1620
# AN1620 stimulus-content-loader for lazy sections: `data-controller="stimulus-content-loader" data-stimulus-content-loader-url-value="/section"` — load expensive sections after initial paint

module Features
  module AN1620
    extend self

    def implemented?
      true
    end

    def spec
      "AN1620 stimulus-content-loader for lazy sections: `data-controller=\"stimulus-content-loader\" data-stimulus-content-loader-url-value=\"/section\"` — load expensive sections after initial paint"
    end
  end
end
