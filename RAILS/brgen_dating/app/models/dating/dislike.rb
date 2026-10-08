# frozen_string_literal: true

class Dating::Dislike < ApplicationRecord
  tracks_activity created: "DatingDislike", source_vertical: "dating", visibility: "private", actor: :disliker

  belongs_to :disliker, class_name: "User"
  belongs_to :dislikee, class_name: "User"
  validates :disliker_id, uniqueness: { scope: :dislikee_id }
  validate  :no_self_dislike

  # Last pass only. Undoing a like is a different decision (it may have
  # created a match), and a rewind that walks the whole history is a log.
  def self.rewind!(user)
    where(disliker_id: user.id).order(created_at: :desc).first&.destroy
  end

  private
  def no_self_dislike
    errors.add(:dislikee, :self_dislike) if disliker_id == dislikee_id
  end
end
