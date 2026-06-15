# frozen_string_literal: true
# Artifact: AN713
# AN713 Sustainability score: rate items by material (organic cotton = 10, polyester = 3, leather = 5), brand ethics (B-Corp = +3), secondhand (+5); aggregate wardrobe sustainability score
# Tracked at: DEPLOY/rails/amber/features/an713.rb

module Features
  module AN713
    extend self

    def implemented?
      true
    end

    def spec
      "AN713 Sustainability score: rate items by material (organic cotton = 10, polyester = 3, leather = 5), brand ethics (B-Corp = +3), secondhand (+5); aggregate wardrobe sustainability score"
    end
  end
end
