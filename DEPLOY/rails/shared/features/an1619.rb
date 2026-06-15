# frozen_string_literal: true
# Artifact: AN1619
# AN1619 stimulus-scroll-progress: `data-controller="stimulus-scroll-progress"` on article layout; shows reading progress bar at top; baibl verse reader, blognet articles

module Features
  module AN1619
    extend self

    def implemented?
      true
    end

    def spec
      "AN1619 stimulus-scroll-progress: `data-controller=\"stimulus-scroll-progress\"` on article layout; shows reading progress bar at top; baibl verse reader, blognet articles"
    end
  end
end
