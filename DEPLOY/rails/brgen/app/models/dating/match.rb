# frozen_string_literal: true

class Dating::Match < ApplicationRecord
  belongs_to :initiator, class_name: "User"
  belongs_to :receiver,  class_name: "User"
  validates :initiator_id, uniqueness: { scope: :receiver_id }
  validates :status, inclusion: { in: %w[pending matched unmatched] }

  scope :active, -> { where(status: "matched") }

  def other_user(user)
    initiator_id == user.id ? receiver : initiator
  end
end
