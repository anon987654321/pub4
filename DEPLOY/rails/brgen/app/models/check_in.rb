# frozen_string_literal: true
# AN625: User check-in

class CheckIn < ApplicationRecord
  belongs_to :user
  belongs_to :place

  after_create_commit :broadcast_to_followers

  private

  def broadcast_to_followers
    user.followers.find_each do |follower|
      ActivityEvent.create!(actor: user, event_type: "check_in", target: place, visibility: "followers")
      Turbo::StreamsChannel.broadcast_prepend_to(follower, target: "activity", partial: "activity_events/check_in", locals: { check_in: self })
    end
  end
end