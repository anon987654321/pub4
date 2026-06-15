# frozen_string_literal: true

class Dating::Match < ApplicationRecord
  # Engine-ized Shared (tranche10)
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:ActivityTrackable) rescue nil

  belongs_to :initiator, class_name: "User"
  belongs_to :receiver,  class_name: "User"
  validates :initiator_id, uniqueness: { scope: :receiver_id }
  validates :status, inclusion: { in: %w[pending matched unmatched] }
  after_create_commit :announce_match

  scope :active, -> { where(status: "matched") }

  def other_user(user)
    initiator_id == user.id ? receiver : initiator
  end

  private

  def announce_match
    return unless status == "matched"

    conversation = Conversation.find_or_create_direct(initiator, receiver)
    [initiator, receiver].each do |user|
      Notification.create!(
        user: user,
        actor: other_user(user),
        kind: "match",
        notifiable: conversation
      )
      Turbo::StreamsChannel.broadcast_append_to(
        "brgen:matches:#{user.id}",
        target: "match-overlays",
        partial: "dating/matches/overlay",
        locals: { match: self, current_user: user, other_user: other_user(user) }
      )
    end
  end
end
