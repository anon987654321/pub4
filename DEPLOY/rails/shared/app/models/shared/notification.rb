# frozen_string_literal: true

module Shared
  class Notification < ApplicationRecord
    self.table_name = "notifications"

    KINDS = %w[like reaction follow mention reply message custom].freeze

    belongs_to :user
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :notifiable, polymorphic: true, optional: true

    validates :kind, inclusion: { in: KINDS }

    scope :unread, -> { where(read_at: nil) }
    scope :recent, -> { order(created_at: :desc) }

    after_create_commit { broadcast_prepend_later_to "shared:notifications:#{user_id}" }

    def read?
      read_at.present?
    end

    def mark_as_read!
      update!(read_at: Time.current)
    end
  end
end
