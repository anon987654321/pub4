# frozen_string_literal: true

class Notification < ApplicationRecord
  KINDS = %w[like reaction follow mention reply message custom].freeze

  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  after_create_commit do
    broadcast_prepend_later_to "brgen:notifications:#{user_id}"
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end
end
