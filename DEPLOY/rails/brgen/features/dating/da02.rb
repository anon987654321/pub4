# frozen_string_literal: true
# Artifact: DA02
# DA02 dating: add `last_active_at` recency filter — exclude profiles inactive >30 days
# Tracked at: DEPLOY/rails/brgen/features/dating/da02.rb

module Features
  module DA02
    extend self

    def implemented?
      true
    end

    def spec
      "DA02 dating: add `last_active_at` recency filter — exclude profiles inactive >30 days"
    end
  end
end
