# frozen_string_literal: true

# Migrated from data/rules.yml STRICT_LOADING_MISSING.
Law.define(:STRICT_LOADING_MISSING) do
  source "Rails strict_loading — N+1 prevention (Rails Guides)"
  severity :info
  languages %i[ruby]
  scope :file
  path "/app/models/"
  absent /\bstrict_loading_by_default\b/
  detect { |text| text.match?(/class\s+\w+\s+<\s+(?:ApplicationRecord|ActiveRecord::Base)\b/m) }
  fix "Add `self.strict_loading_by_default = true` to surface missing eager-loads."
  bad <<~X
    class User < ApplicationRecord
    end
  X
  good <<~X
    class User < ApplicationRecord
      self.strict_loading_by_default = true
    end
  X
end
