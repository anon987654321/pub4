# frozen_string_literal: true
# Artifact: AN1708
# AN1708 counter_cache with touch: `belongs_to :post, counter_cache: true, touch: true` — free comment_count on posts, free cache invalidation; zero SQL overhead in views

module Features
  module AN1708
    extend self

    def implemented?
      true
    end

    def spec
      "AN1708 counter_cache with touch: `belongs_to :post, counter_cache: true, touch: true` — free comment_count on posts, free cache invalidation; zero SQL overhead in views"
    end
  end
end
