# frozen_string_literal: true
# Artifact: AN1213
# AN1213 Prefetch on hover: `data-turbo-prefetch` triggers on mouseenter (200ms threshold); reduces perceived navigation time to near-zero
# Tracked at: DEPLOY/rails/shared/features/an1213.rb

module Features
  module AN1213
    extend self

    def implemented?
      true
    end

    def spec
      "AN1213 Prefetch on hover: `data-turbo-prefetch` triggers on mouseenter (200ms threshold); reduces perceived navigation time to near-zero"
    end
  end
end
