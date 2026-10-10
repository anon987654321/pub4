# frozen_string_literal: true

class Dating::PathCrossing < ApplicationRecord
  self.table_name = "dating_path_crossings"

  belongs_to :city
  belongs_to :user_a, class_name: "User"
  belongs_to :user_b, class_name: "User"
  belongs_to :neighborhood, optional: true

  validates :crossed_at, :crossing_on, presence: true
  validate :different_people
  validate :canonical_pair

  scope :recent, ->(since = 14.days.ago) { where("crossed_at >= ?", since) }

  def self.for_user(user_id)
    where("user_a_id = :id OR user_b_id = :id", id: user_id)
  end

  def other_user_id(user_id)
    user_a_id == user_id.to_i ? user_b_id : user_a_id
  end

  private

  def different_people
    errors.add(:user_b_id, :invalid) if user_a_id.present? && user_a_id == user_b_id
  end

  def canonical_pair
    return if user_a_id.blank? || user_b_id.blank?

    errors.add(:base, :invalid) unless user_a_id < user_b_id
  end
end
