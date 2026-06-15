# frozen_string_literal: true
# Artifact: AN1108
# AN1108 Donation receipt: email receipt with item list and estimated value for tax deduction purposes (Norwegian fradrag)
# Tracked at: DEPLOY/rails/hjerterom/features/an1108.rb

module Features
  module AN1108
    extend self

    def implemented?
      true
    end

    def spec
      "AN1108 Donation receipt: email receipt with item list and estimated value for tax deduction purposes (Norwegian fradrag)"
    end
  end
end
