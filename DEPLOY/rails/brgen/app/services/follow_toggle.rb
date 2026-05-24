# frozen_string_literal: true

class FollowToggle
  def self.call(follower:, followed:)
    new(follower:, followed:).call
  end

  def initialize(follower:, followed:)
    @follower = follower
    @followed = followed
  end

  def call
    return false if follower == followed

    follow = Follow.find_by(follower:, followed:)
    active = follow.nil?
    active ? Follow.create!(follower:, followed:) : follow.destroy!

    Shared::EventEmitter.call("brgen.follow.toggled", follower_id: follower.id, followed_id: followed.id, active:) if defined?(Shared::EventEmitter)
    active
  end

  private

  attr_reader :follower, :followed
end
