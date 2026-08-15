# frozen_string_literal: true

module Shared
  class Notification < ApplicationRecord
    self.table_name = "notifications"

    KINDS = %w[like reaction follow mention reply message match order alert custom].freeze

    belongs_to :user
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :notifiable, polymorphic: true, optional: true

    validates :kind, inclusion: { in: KINDS }

    scope :unread, -> { where(read_at: nil) }
    scope :recent, -> { order(created_at: :desc) }

    # No broadcast: nothing subscribes to shared:notifications:<user_id> and no
    # shared/notifications/_notification partial exists (brgen's is app-local at a
    # different path). Restore as an explicit broadcast_prepend_later_to with a
    # partial: when a subscriber lands. Pinned by turbo_broadcast_contract_test.rb.

    def read?
      read_at.present?
    end

    def mark_as_read!
      update!(read_at: Time.current)
    end
  end
end
