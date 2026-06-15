# frozen_string_literal: true

class Dating::Like < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "DatingLike", source_vertical: "dating", visibility: "private", actor: :liker

  belongs_to :liker, class_name: "User"
  belongs_to :likee, class_name: "User"
  validates :liker_id, uniqueness: { scope: :likee_id }
  validate  :no_self_like
  after_create :check_mutual_match

  private

  def no_self_like
    errors.add(:likee, "can't like yourself") if liker_id == likee_id
  end

  def check_mutual_match
    return unless Dating::Like.exists?(liker_id: likee_id, likee_id: liker_id)
    Dating::Match.find_or_create_by!(initiator_id: liker_id, receiver_id: likee_id) do |m|
      m.status = "matched"
    end
  end
end
