# frozen_string_literal: true
# Artifact: AN1210
# AN1210 Image optimization: ImageProcessing::Vips for all Active Storage variants; convert to WebP; serve via `<picture>` with JPEG fallback; lazy load all
# Tracked at: DEPLOY/rails/shared/features/an1210.rb

module Features
  module AN1210
    extend self

    def implemented?
      true
    end

    def spec
      "AN1210 Image optimization: ImageProcessing::Vips for all Active Storage variants; convert to WebP; serve via `<picture>` with JPEG fallback; lazy load all"
    end
  end
end
