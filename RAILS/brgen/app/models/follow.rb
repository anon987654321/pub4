# frozen_string_literal: true

class Follow < ApplicationRecord
  tracks_activity created: "FollowCreated", source_vertical: "social", actor: :follower

  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate :no_self_follow

  after_create_commit :emit_follow_created
  after_destroy_commit :emit_follow_removed

  private

  def no_self_follow
    errors.add(:base, :self_follow) if follower_id == followed_id
  end

  def emit_follow_created
    followed.notifications.create!(actor: follower, kind: "follow", notifiable: self)
    Shared::EventEmitter.call("brgen.follow.created", follower_id:, followed_id:) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Rails.logger.warn("Follow notification skipped: #{e.class}: #{e.message}")
  end

  def emit_follow_removed
    Shared::EventEmitter.call("brgen.follow.removed", follower_id:, followed_id:) if defined?(Shared::EventEmitter)
  end
end
