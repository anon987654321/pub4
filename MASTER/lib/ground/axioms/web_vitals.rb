# frozen_string_literal: true

module Master
  module Ground
  module Axioms
  module WebVitals
    LCP_GOOD_S = 2.0
    LCP_NEEDS_IMPROVEMENT_S = 4.0
    INP_GOOD_MS = 200
    INP_NEEDS_IMPROVEMENT_MS = 500
    CLS_GOOD = 0.1
    CLS_NEEDS_IMPROVEMENT = 0.25

    FONT_DISPLAY_SWAP = "swap"
    BODY_LINE_HEIGHT = 1.5
    MEASURE_CH = 65
    TYPE_SCALE_RATIO = 1.25
    BASE_FONT_PX = 16

    def self.lcp_grade(seconds)
      return :good if seconds <= LCP_GOOD_S
      return :needs_improvement if seconds <= LCP_NEEDS_IMPROVEMENT_S
      :poor
    end

    def self.inp_grade(ms)
      return :good if ms <= INP_GOOD_MS
      return :needs_improvement if ms <= INP_NEEDS_IMPROVEMENT_MS
      :poor
    end

    def self.cls_grade(score)
      return :good if score <= CLS_GOOD
      return :needs_improvement if score <= CLS_NEEDS_IMPROVEMENT
      :poor
    end
  end
  end
  end
end
