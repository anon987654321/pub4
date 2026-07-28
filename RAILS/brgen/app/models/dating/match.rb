# frozen_string_literal: true

class Dating::Match < ApplicationRecord
  # Engine-ized Shared (tranche10)
  include Shared::Notifiable
  include Shared::StrictSafeAssociations
  tracks_activity created: "DatingMatch", source_vertical: "dating", visibility: "private", actor: :initiator

  belongs_to :initiator, class_name: "User"
  belongs_to :receiver,  class_name: "User"
  validates :initiator_id, uniqueness: { scope: :receiver_id }
  validates :status, inclusion: { in: %w[pending matched unmatched] }
  after_create_commit :announce_match

  scope :active, -> { where(status: "matched") }

  # Called from views and from announce_match's notification path, on matches
  # that were found by id — nothing preloaded, and ApplicationRecord is
  # strict_loading by default, so the plain association read raised. Same shape
  # as Marketplace::Order#seller and Takeaway::Order#delivery_fee.
  def other_user(user)
    initiator_id == user.id ? strict_safe(:receiver) : strict_safe(:initiator)
  end

  private

  def announce_match
    return unless status == "matched"

    conversation = Conversation.find_or_create_direct(initiator, receiver)
    [ initiator, receiver ].each do |user|
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
