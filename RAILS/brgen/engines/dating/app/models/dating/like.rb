# frozen_string_literal: true

class Dating::Like < ApplicationRecord
  tracks_activity created: "DatingLike", source_vertical: "dating", visibility: "private", actor: :liker

  belongs_to :liker, class_name: "User"
  belongs_to :likee, class_name: "User"
  # Hinge's whole interaction: the like points at the thing it is about, and
  # optionally says something. Both optional, because a plain like is still a
  # like — a product that refuses one is a product people stop using at 1am.
  belongs_to :dating_prompt, class_name: "Dating::Prompt", optional: true

  validates :liker_id, uniqueness: { scope: :likee_id }
  validates :comment, length: { maximum: 280 }
  validate  :no_self_like
  after_create :check_mutual_match

  # What "who liked you" reads. Excludes anyone the viewer has already answered,
  # in either direction — a list that keeps showing people you already matched
  # with is a list nobody opens twice.
  scope :waiting_on, lambda { |user|
    answered = Dating::Like.where(liker_id: user.id).select(:likee_id)
    disliked = Dating::Dislike.where(disliker_id: user.id).select(:dislikee_id)
    where(likee_id: user.id).where.not(liker_id: answered).where.not(liker_id: disliked)
  }

  def commented? = comment.present?

  private

  def no_self_like
    errors.add(:likee, :self_like) if liker_id == likee_id
  end

  def check_mutual_match
    return unless Dating::Like.exists?(liker_id: likee_id, likee_id: liker_id)
    Dating::Match.find_or_create_by!(initiator_id: liker_id, receiver_id: likee_id) do |m|
      m.status = "matched"
    end
  end
end
