# frozen_string_literal: true
# AN612: Marketplace image variants

module Marketplace
  class ImageVariants
    VARIANTS = { thumb: [80, 80], card: [400, 400], full: [1200, 1200] }.freeze

    def self.generate(attachment)
      VARIANTS.transform_values do |(w, h)|
        attachment.variant(resize_to_limit: [w, h], format: :webp).processed
      end
    end
  end
end