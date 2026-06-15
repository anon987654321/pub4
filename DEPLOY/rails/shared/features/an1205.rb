# frozen_string_literal: true
# Artifact: AN1205
# AN1205 Counter caches: add `counter_cache: true` for comment_count, vote_count, follower_count, listing_count on all association-heavy models
# Tracked at: DEPLOY/rails/shared/features/an1205.rb

module Features
  module AN1205
    extend self

    def implemented?
      true
    end

    def spec
      "AN1205 Counter caches: add `counter_cache: true` for comment_count, vote_count, follower_count, listing_count on all association-heavy models"
    end
  end
end
