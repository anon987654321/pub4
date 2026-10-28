# frozen_string_literal: true

require_relative "improve/opportunity"
require_relative "improve/domains"
require_relative "improve/ideate"
require_relative "improve/restructure"
require_relative "improve/engine"

module Master
  module Fix
    # The Elevation Engine — the half of /fix that does not repair: it improves,
    # ideates and restructures. Where the scanner measures distance from the law,
    # elevation measures distance from the ideal, and closes it one anchored,
    # evidence-backed step per pass. /fix embodies what it performs: the engine is
    # itself small, single-purpose files that name their law.
    module Improve
      LAW_ID = "ELEVATION_IDEAL"

      # Severity rides the improvement lane: elevation never blocks a run.
      SEVERITY = 3
      CONFIDENCE = 0.8
      MAX_FINDINGS = 8
    end
  end
end
