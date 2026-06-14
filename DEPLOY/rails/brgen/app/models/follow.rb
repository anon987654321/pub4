# frozen_string_literal: true

class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate :no_self_follow

  after_create_commit :emit_follow_created
  after_destroy_commit :emit_follow_removed

  private

  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == followed_id
  end

  def emit_follow_created
    Shared::Notifiable.deliver_notification(followed, actor: follower, kind: "follow", source: self)
    Shared::EventEmitter.call("brgen.follow.created", follower_id:, followed_id:) if defined?(Shared::EventEmitter)
  end

  def emit_follow_removed
    Shared::EventEmitter.call("brgen.follow.removed", follower_id:, followed_id:) if defined?(Shared::EventEmitter)
  end
end
