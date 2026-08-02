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

    # No broadcast: nothing subscribes to shared:review_cases and no
    # shared/review_cases/_review_case partial exists. amber creates these rows
    # (ReportsController), so an implicit broadcast here WOULD enqueue a job that
    # raises MissingTemplate — the one live crash path of the three. Restore as an
    # explicit broadcast with a partial: when a moderation stream is built. Pinned
    # by turbo_broadcast_contract_test.rb.

    def close!(user)
      update!(state: "closed", reviewer: user, reviewed_at: Time.current)
    end

    def ignore!(user)
      update!(state: "ignored", reviewer: user, reviewed_at: Time.current)
    end
  end
end
