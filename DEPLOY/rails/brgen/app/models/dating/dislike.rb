# frozen_string_literal: true

class Dating::Dislike < ApplicationRecord
  belongs_to :disliker, class_name: "User"
  belongs_to :dislikee, class_name: "User"
  validates :disliker_id, uniqueness: { scope: :dislikee_id }
  validate  :no_self_dislike

  private
  def no_self_dislike
    errors.add(:dislikee, "can't dislike yourself") if disliker_id == dislikee_id
  end
end
