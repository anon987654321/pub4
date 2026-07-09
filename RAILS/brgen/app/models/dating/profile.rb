# frozen_string_literal: true

class Dating::Profile < ApplicationRecord
  include CityTenantable

  tracks_activity created: "DatingProfileCreated", updated: "DatingProfileUpdated", source_vertical: "dating", visibility: "private", actor: :user
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  include Shared::Reactable
  belongs_to :user
  belongs_to :neighborhood, optional: true
  has_many_attached :photos
  process_media_variants :photos, variants: {
    thumb: { resize_to_limit: [ 400, 600 ], format: :webp },
    card: { resize_to_limit: [ 800, 1_200 ], format: :webp }
  }

  GENDERS     = %w[man woman nonbinary other].freeze
  LOOKING_FOR = %w[man woman everyone].freeze

  validates :bio,         length: { maximum: 500 }
  validates :age,         numericality: { greater_than: 17, less_than: 100 }, allow_nil: true
  validates :gender,      inclusion: { in: GENDERS },     allow_nil: true
  validates :looking_for, inclusion: { in: LOOKING_FOR }, allow_nil: true
  validate :photos_present_when_visible, on: :update

  scope :visible, -> { where(visible: true) }
  # nearby (bbox) + haversine provided by concern; old approx replaced for consistency
  scope :in_neighborhood, ->(neigh) { neigh ? where(neighborhood_id: neigh.id) : all }

  def name = user.display_name

  def liked_by?(user)    = Dating::Like.exists?(liker: user, likee: self.user)
  def disliked_by?(user) = Dating::Dislike.exists?(disliker: user, dislikee: self.user)
  def matched_with?(user)
    Dating::Match.where(status: "matched")
      .where("(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)",
             self.user_id, user.id, user.id, self.user_id).exists?
  end

  private

  def photos_present_when_visible
    return unless visible?
    return if photos.attached?

    errors.add(:photos, "must include at least one photo when visible")
  end
end
