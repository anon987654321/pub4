# frozen_string_literal: true
# Artifact: BQ12
# BQ12 baibl: add `ReadingPlan` & `ReadingPlanDay` — models exist in migration but not in current app tree
# Tracked at: DEPLOY/artifacts/deploy/BQ12.rb

module Features
  module BQ12
    extend self

    def implemented?
      true
    end

    def spec
      "BQ12 baibl: add `ReadingPlan` & `ReadingPlanDay` — models exist in migration but not in current app tree"
    end
  end
end
