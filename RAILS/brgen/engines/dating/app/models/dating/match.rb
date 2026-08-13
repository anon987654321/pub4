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

  # Either direction: uniqueness is initiator+receiver, so A→B and B→A are
  # different rows. Mutual likes create one of those; rematch must find it.
  def self.between(user_a, user_b)
    a_id = user_a.respond_to?(:id) ? user_a.id : user_a
    b_id = user_b.respond_to?(:id) ? user_b.id : user_b
    where(initiator_id: a_id, receiver_id: b_id)
      .or(where(initiator_id: b_id, receiver_id: a_id))
      .first
  end

  def involves?(user)
    user_id = user.respond_to?(:id) ? user.id : user
    initiator_id == user_id || receiver_id == user_id
  end

  # Called from views and from announce_match's notification path, on matches
  # that were found by id — nothing preloaded, and ApplicationRecord is
  # strict_loading by default, so the plain association read raised. Same shape
  # as Marketplace::Order#seller and Takeaway::Order#delivery_fee.
  def other_user(user)
    initiator_id == user.id ? strict_safe(:receiver) : strict_safe(:initiator)
  end

  # Status exists so a match can end without deleting the row. The likes have
  # to go with it: uniqueness on liker+likee would otherwise make rematch
  # impossible, and check_mutual_match only runs after_create.
  def unmatch!
    return false unless status == "matched"

    transaction do
      Dating::Like.where(
        "(liker_id = :a AND likee_id = :b) OR (liker_id = :b AND likee_id = :a)",
        a: initiator_id, b: receiver_id
      ).delete_all
      update!(status: "unmatched")
    end
    true
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
