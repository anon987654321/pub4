# frozen_string_literal: true
# Artifact: BR10
# BR10 hjerterom donation form: add `data-reflex="change->Donation#calculate_impact"` for real-time impact estimate
# Tracked at: DEPLOY/artifacts/deploy/BR10.rb

module Features
  module BR10
    extend self

    def implemented?
      true
    end

    def spec
      "BR10 hjerterom donation form: add `data-reflex=\"change->Donation#calculate_impact\"` for real-time impact estimate"
    end
  end
end
