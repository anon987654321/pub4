# frozen_string_literal: true

# A one-way mute-and-hide: blocker no longer sees blocked's content. Silent by
# design — the blocked user is never notified.
class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocker_id, uniqueness: { scope: :blocked_id }
  validate :no_self_block

  private

  def no_self_block
    errors.add(:base, "cannot block yourself") if blocker_id == blocked_id
  end
end
