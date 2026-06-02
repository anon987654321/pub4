# frozen_string_literal: true

class Dating::Profile < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood, optional: true
  has_many_attached :photos

  GENDERS     = %w[man woman nonbinary other].freeze
  LOOKING_FOR = %w[man woman everyone].freeze

  validates :bio,         length: { maximum: 500 }
  validates :age,         numericality: { greater_than: 17, less_than: 100 }, allow_nil: true
  validates :gender,      inclusion: { in: GENDERS },     allow_nil: true
  validates :looking_for, inclusion: { in: LOOKING_FOR }, allow_nil: true

  scope :visible, -> { where(visible: true) }
  scope :nearby, ->(lat, lng, km = 50) {
    where("ABS(latitude - ?) < ? AND ABS(longitude - ?) < ?", lat, km / 111.0, lng, km / 111.0)
  }
  scope :in_neighborhood, ->(neigh) { neigh ? where(neighborhood_id: neigh.id) : all }

  def liked_by?(user)    = Dating::Like.exists?(liker: user, likee: self.user)
  def disliked_by?(user) = Dating::Dislike.exists?(disliker: user, dislikee: self.user)
  def matched_with?(user)
    Dating::Match.where(status: "matched")
      .where("(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)",
             self.user_id, user.id, user.id, self.user_id).exists?
  end
end
