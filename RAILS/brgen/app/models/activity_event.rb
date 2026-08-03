# frozen_string_literal: true

class ActivityEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :source_vertical, :event_name, :object_type, :object_id, presence: true

  scope :visible, -> { where(moderation_state: "clean") }
  scope :recent, -> { order(created_at: :desc) }
  # Never surface private activity on a public profile (dating likes are private).
  scope :public_only, -> { where(visibility: "public") }
end
