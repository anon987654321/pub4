# frozen_string_literal: true

module Shared
  class ReviewCase < ApplicationRecord
    self.table_name = "review_cases"

    STATES = %w[open reviewing closed ignored].freeze
    REASONS = %w[spam abuse duplicate off_topic unsafe other].freeze

    belongs_to :reporter, class_name: "User", optional: true
    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :reviewable, polymorphic: true

    validates :state, inclusion: { in: STATES }
    validates :reason, inclusion: { in: REASONS }, allow_blank: true

    scope :active, -> { where(state: %w[open reviewing]) }
    scope :recent, -> { order(created_at: :desc) }

    after_create_commit { broadcast_prepend_later_to "shared:review_cases" }
    after_update_commit { broadcast_replace_later_to "shared:review_cases" }

    def close!(user)
      update!(state: "closed", reviewer: user, reviewed_at: Time.current)
    end

    def ignore!(user)
      update!(state: "ignored", reviewer: user, reviewed_at: Time.current)
    end
  end
end
